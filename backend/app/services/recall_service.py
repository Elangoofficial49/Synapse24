from datetime import datetime
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from fastapi import HTTPException

from app.models import (
    Batch, BatchStatus, PackageStatus, Product, Recall, RecallSeverity,
    RecallStatus, SerializedPackage, User, UserRole, Organization,
    Shipment, ShipmentItem, RecallAcknowledgement,
)
from app.blockchain.factory import get_blockchain_adapter

class RecallService:
    @staticmethod
    async def initiate_batch_recall(
        db: AsyncSession,
        batch_id: str,
        user: User,
        reason: str,
        severity: RecallSeverity
    ) -> Recall:
        batch = await db.get(Batch, batch_id)
        if not batch:
            raise HTTPException(status_code=404, detail="Batch not found")
        product = await db.get(Product, batch.product_id)
        if (
            not product
            or (
                user.role != UserRole.ADMIN
                and product.manufacturer_id != user.organization_id
            )
        ):
            raise HTTPException(
                status_code=403,
                detail="You can only recall batches manufactured by your organization.",
            )

        # Mark batch as recalled
        batch.status = BatchStatus.RECALLED
        batch.recall_reason = reason

        # Mark all serialized packages in this batch as recalled
        stmt = (
            update(SerializedPackage)
            .where(SerializedPackage.batch_id == batch.id)
            .values(status=PackageStatus.RECALLED)
        )
        await db.execute(stmt)

        # Count affected packages
        pkg_count = (await db.execute(
            select(SerializedPackage).where(SerializedPackage.batch_id == batch.id)
        )).scalars().all()

        recall = Recall(
            batch_id=batch.id,
            initiated_by=user.id,
            recall_reason=reason,
            severity=severity,
            affected_package_count=len(pkg_count),
            status=RecallStatus.ACTIVE
        )
        db.add(recall)

        adapter = get_blockchain_adapter()
        await adapter.recall_batch({
            "batch_id": batch.id,
            "batch_number": batch.batch_number,
            "initiated_by": user.id,
            "reason": reason,
            "affected_count": len(pkg_count)
        })

        await db.commit()
        await db.refresh(recall)
        return recall

    @staticmethod
    async def get_recall_impact_simulation(db: AsyncSession, batch_id: str) -> dict:
        """
        Recall Impact Simulator:
        Traces batch across all recorded supply-chain transfers (Manufacturer -> Distributors -> Pharmacies).
        Computes actual recorded quantities, receipt statuses, acknowledgement statuses, and unresolved quantities.
        """
        batch = await db.get(Batch, batch_id)
        if not batch:
            raise HTTPException(status_code=404, detail="Batch not found")
        product = await db.get(Product, batch.product_id)
        manufacturer = await db.get(Organization, product.manufacturer_id) if product else None

        # Fetch active recall if any
        recall_res = await db.execute(
            select(Recall).where(Recall.batch_id == batch.id).order_by(Recall.created_at.desc())
        )
        recall = recall_res.scalars().first()

        # Fetch all packages for this batch
        pkg_res = await db.execute(
            select(SerializedPackage).where(SerializedPackage.batch_id == batch.id)
        )
        packages = pkg_res.scalars().all()
        pkg_ids = [p.id for p in packages]

        # Trace all shipments carrying packages of this batch
        shipments_res = await db.execute(
            select(Shipment, ShipmentItem)
            .join(ShipmentItem, Shipment.id == ShipmentItem.shipment_id)
            .where(ShipmentItem.package_id.in_(pkg_ids))
            .order_by(Shipment.dispatch_timestamp.asc())
        )
        shipment_rows = shipments_res.all()

        # Map organizations involved downstream
        distributor_map: dict[str, dict] = {}
        pharmacy_map: dict[str, dict] = {}

        for shipment, item in shipment_rows:
            receiver = await db.get(Organization, shipment.receiver_org_id)
            if not receiver:
                continue

            entry = {
                "organization_id": receiver.id,
                "name": receiver.name,
                "org_type": receiver.org_type.value,
                "shipment_id": shipment.id,
                "shipment_reference": shipment.shipment_reference,
                "status": shipment.status.value,
                "dispatched_qty": shipment.declared_quantity,
                "received_qty": shipment.received_quantity or 0,
                "dispatch_timestamp": shipment.dispatch_timestamp.isoformat() if shipment.dispatch_timestamp else None,
                "receipt_timestamp": shipment.receipt_timestamp.isoformat() if shipment.receipt_timestamp else None,
            }

            if receiver.org_type.value == "distributor":
                distributor_map[receiver.id] = entry
            elif receiver.org_type.value == "pharmacy":
                pharmacy_map[receiver.id] = entry

        # Fetch acknowledgements
        acks: list[dict] = []
        acknowledged_org_ids = set()
        quarantined_sum = 0
        if recall:
            from app.models import RecallAcknowledgement
            ack_res = await db.execute(
                select(RecallAcknowledgement, Organization.name)
                .join(Organization, RecallAcknowledgement.organization_id == Organization.id)
                .where(RecallAcknowledgement.recall_id == recall.id)
            )
            for ack, org_name in ack_res.all():
                acknowledged_org_ids.add(ack.organization_id)
                quarantined_sum += ack.quarantined_quantity
                acks.append({
                    "organization_id": ack.organization_id,
                    "organization_name": org_name,
                    "acknowledged_at": ack.created_at.isoformat(),
                    "quarantined_quantity": ack.quarantined_quantity,
                    "notes": ack.response_notes,
                    "tx_ref": ack.blockchain_tx_ref,
                })

        # Calculate actual recorded quantities
        total_manufactured = batch.quantity_manufactured
        total_serialized = len(packages)
        explicit_quarantined_pkgs = sum(1 for p in packages if p.status == PackageStatus.QUARANTINED)
        effective_quarantined = quarantined_sum if quarantined_sum > 0 else explicit_quarantined_pkgs

        downstream_orgs = list(distributor_map.values()) + list(pharmacy_map.values())
        unresponded_orgs = [
            org["name"] for org in downstream_orgs
            if org["organization_id"] not in acknowledged_org_ids
        ]

        return {
            "batch_id": batch.id,
            "batch_number": batch.batch_number,
            "product_name": product.name if product else None,
            "manufacturer_name": manufacturer.name if manufacturer else None,
            "is_recalled": recall is not None,
            "recall_reason": recall.recall_reason if recall else batch.recall_reason,
            "severity": recall.severity.value if recall else None,
            "initiated_at": recall.created_at.isoformat() if recall else None,
            "quantities": {
                "manufactured": total_manufactured,
                "serialized": total_serialized,
                "quarantined": effective_quarantined,
                "unresolved": max(0, total_serialized - effective_quarantined),
            },
            "distributors": list(distributor_map.values()),
            "pharmacies": list(pharmacy_map.values()),
            "acknowledgements": acks,
            "unresponded_organizations": unresponded_orgs,
        }

    @staticmethod
    async def acknowledge_recall(
        db: AsyncSession,
        recall_id: str,
        user: User,
        quarantined_quantity: int,
        response_notes: Optional[str] = None
    ) -> dict:
        from app.models import RecallAcknowledgement
        recall = await db.get(Recall, recall_id)
        if not recall:
            raise HTTPException(status_code=404, detail="Recall not found")

        adapter = get_blockchain_adapter()
        tx = await adapter.quarantine_package({
            "recall_id": recall.id,
            "batch_id": recall.batch_id,
            "organization_id": user.organization_id,
            "quarantined_quantity": quarantined_quantity,
            "user_id": user.id
        })

        ack = RecallAcknowledgement(
            recall_id=recall.id,
            organization_id=user.organization_id,
            acknowledged_by=user.id,
            quarantined_quantity=quarantined_quantity,
            response_notes=response_notes,
            blockchain_tx_ref=tx.get("tx_id"),
        )
        db.add(ack)
        await db.commit()
        await db.refresh(ack)

        return {
            "status": "success",
            "acknowledgement_id": ack.id,
            "quarantined_quantity": ack.quarantined_quantity,
            "blockchain_tx_ref": ack.blockchain_tx_ref,
        }
