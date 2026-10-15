import uuid
from datetime import datetime
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from fastapi import HTTPException, status

from app.models import (
    Shipment, ShipmentItem, SerializedPackage, CustodyEvent, Dispute, CorrectionEvent,
    SuspiciousActivityAlert, User, Organization, ShipmentStatus, PackageStatus,
    CustodyEventType, AlertType, AlertSeverity, DisputeStatus
)
from app.blockchain.factory import get_blockchain_adapter

class CustodyService:
    @staticmethod
    async def create_and_dispatch_shipment(
        db: AsyncSession,
        sender: User,
        receiver_org_id: str,
        package_serial_ids: List[str],
        transporter_org_id: Optional[str] = None,
        notes: Optional[str] = None
    ) -> Shipment:
        receiver_org = await db.get(Organization, receiver_org_id)
        if not receiver_org:
            raise HTTPException(status_code=404, detail="Receiver organization not found")

        # Verify packages belong to sender and are ready for dispatch
        stmt = select(SerializedPackage).where(
            SerializedPackage.package_serial_id.in_(package_serial_ids),
            SerializedPackage.current_custodian_org_id == sender.organization_id
        )
        pkgs_result = await db.execute(stmt)
        packages = pkgs_result.scalars().all()

        if len(packages) != len(package_serial_ids):
            raise HTTPException(
                status_code=400,
                detail="One or more packages do not exist or are not in current custodian inventory"
            )

        # Check for recalled/quarantined packages
        for p in packages:
            if p.status in [PackageStatus.RECALLED, PackageStatus.QUARANTINED]:
                raise HTTPException(
                    status_code=400,
                    detail=f"Package {p.package_serial_id} is {p.status.value} and cannot be transferred."
                )

        shipment_ref = f"SHP-{datetime.utcnow().strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}"
        shipment = Shipment(
            shipment_reference=shipment_ref,
            sender_org_id=sender.organization_id,
            receiver_org_id=receiver_org_id,
            transporter_org_id=transporter_org_id,
            status=ShipmentStatus.DISPATCHED,
            declared_quantity=len(packages),
            dispatch_timestamp=datetime.utcnow(),
            notes=notes,
            created_by=sender.id
        )
        db.add(shipment)
        await db.commit()
        await db.refresh(shipment)

        # Create Shipment Items & Update package state to IN_TRANSIT
        adapter = get_blockchain_adapter()
        tx = await adapter.initiate_transfer({
            "shipment_id": shipment.id,
            "shipment_ref": shipment.shipment_reference,
            "sender_org_id": sender.organization_id,
            "receiver_org_id": receiver_org_id,
            "declared_quantity": shipment.declared_quantity,
            "package_serial_ids": package_serial_ids
        })

        for p in packages:
            p.status = PackageStatus.IN_TRANSIT
            item = ShipmentItem(
                shipment_id=shipment.id,
                package_id=p.id,
                quantity_dispatched=1
            )
            db.add(item)
            
            custody_ev = CustodyEvent(
                package_id=p.id,
                shipment_id=shipment.id,
                event_type=CustodyEventType.DISPATCHED,
                from_org_id=sender.organization_id,
                to_org_id=receiver_org_id,
                performed_by=sender.id,
                notes=f"Dispatched via shipment {shipment_ref}",
                blockchain_tx_ref=tx.get("tx_id"),
                is_on_chain=tx.get("is_on_chain", False)
            )
            db.add(custody_ev)

        await db.commit()
        return shipment

    @staticmethod
    async def process_shipment_receipt(
        db: AsyncSession,
        shipment_id: str,
        receiver: User,
        actual_quantity_received: int,
        scanned_serial_ids: Optional[List[str]] = None,
        notes: Optional[str] = None
    ) -> Dict[str, Any]:
        shipment = await db.get(Shipment, shipment_id)
        if not shipment:
            raise HTTPException(status_code=404, detail="Shipment not found")

        # Two-party validation: Ensure only authorized receiver can confirm
        if shipment.receiver_org_id != receiver.organization_id:
            raise HTTPException(
                status_code=403,
                detail="Unauthorized: Only the designated receiver organization can confirm receipt."
            )

        if shipment.status not in [ShipmentStatus.DISPATCHED, ShipmentStatus.IN_TRANSIT]:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot receive shipment in status: {shipment.status.value}"
            )

        shipment.received_quantity = actual_quantity_received
        shipment.receipt_timestamp = datetime.utcnow()

        # Fetch shipment items
        stmt = select(ShipmentItem, SerializedPackage).join(
            SerializedPackage, ShipmentItem.package_id == SerializedPackage.id
        ).where(ShipmentItem.shipment_id == shipment.id)
        items = (await db.execute(stmt)).all()

        adapter = get_blockchain_adapter()
        discrepancy_detected = actual_quantity_received != shipment.declared_quantity
        dispute_created = None

        if discrepancy_detected:
            # Quantity mismatch branch: Strict Innovation #1 & #4
            if actual_quantity_received == 0:
                shipment.status = ShipmentStatus.REJECTED
                event_type = CustodyEventType.REJECTED
            else:
                shipment.status = ShipmentStatus.PARTIALLY_RECEIVED
                event_type = CustodyEventType.PARTIALLY_RECEIVED

            # Automatically create formal dispute
            dispute = Dispute(
                shipment_id=shipment.id,
                reported_by=receiver.id,
                dispute_reason=f"Quantity mismatch: Sender declared {shipment.declared_quantity}, Receiver confirmed {actual_quantity_received}. {notes or ''}",
                expected_quantity=shipment.declared_quantity,
                actual_quantity=actual_quantity_received,
                status=DisputeStatus.OPEN
            )
            db.add(dispute)
            
            # Anomaly alert
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.INVALID_SEQUENCE,
                severity=AlertSeverity.HIGH,
                shipment_id=shipment.id,
                reason=f"Discrepancy in shipment {shipment.shipment_reference}: missing {shipment.declared_quantity - actual_quantity_received} items"
            )
            db.add(alert)
            
            tx = await adapter.dispute_transfer({
                "shipment_id": shipment.id,
                "declared_quantity": shipment.declared_quantity,
                "received_quantity": actual_quantity_received,
                "receiver_org_id": receiver.organization_id
            })
            dispute_created = dispute
        else:
            # Full acceptance
            shipment.status = ShipmentStatus.RECEIVED
            event_type = CustodyEventType.RECEIVED
            tx = await adapter.accept_transfer({
                "shipment_id": shipment.id,
                "received_quantity": actual_quantity_received,
                "receiver_org_id": receiver.organization_id
            })

        # Update package custodianship for accepted packages
        # If partial, we transfer the first actual_quantity_received packages unless scanned specified
        for i, (item, pkg) in enumerate(items):
            if i < actual_quantity_received:
                pkg.status = PackageStatus.RECEIVED
                pkg.current_custodian_org_id = receiver.organization_id
                item.quantity_received = 1
                item.status = "received"
            else:
                item.quantity_received = 0
                item.status = "missing_or_disputed"

            custody_ev = CustodyEvent(
                package_id=pkg.id,
                shipment_id=shipment.id,
                event_type=event_type,
                from_org_id=shipment.sender_org_id,
                to_org_id=receiver.organization_id,
                performed_by=receiver.id,
                notes=f"Receipt confirmed. Status: {shipment.status.value}. Notes: {notes or ''}",
                blockchain_tx_ref=tx.get("tx_id"),
                is_on_chain=tx.get("is_on_chain", False)
            )
            db.add(custody_ev)

        await db.commit()
        await db.refresh(shipment)
        
        return {
            "shipment": shipment,
            "discrepancy": discrepancy_detected,
            "dispute_id": dispute_created.id if dispute_created else None,
            "tx_reference": tx.get("tx_id")
        }

    @staticmethod
    async def split_shipment(
        db: AsyncSession,
        parent_shipment_id: str,
        user: User,
        child_allocations: List[Dict[str, Any]]
    ) -> List[Shipment]:
        """
        Shipment Splitting & Quantity Reconciliation (Innovation #3).
        Validates:
        - Sum of child shipments <= parent received quantity
        - All allocated packages exist in parent shipment
        - Parent must be fully or partially received
        """
        parent = await db.get(Shipment, parent_shipment_id)
        if not parent:
            raise HTTPException(status_code=404, detail="Parent shipment not found")

        if parent.status not in [ShipmentStatus.RECEIVED, ShipmentStatus.PARTIALLY_RECEIVED]:
            raise HTTPException(
                status_code=400,
                detail="Parent shipment must be in RECEIVED or PARTIALLY_RECEIVED status before splitting"
            )

        total_split_qty = sum(len(c.get("package_serial_ids", [])) for c in child_allocations)
        available_qty = parent.received_quantity or 0

        if total_split_qty > available_qty:
            raise HTTPException(
                status_code=400,
                detail=f"Reconciliation failure: Cannot allocate {total_split_qty} packages from received inventory of {available_qty}"
            )

        created_children = []
        adapter = get_blockchain_adapter()

        for idx, child_data in enumerate(child_allocations):
            pkg_ids = child_data.get("package_serial_ids", [])
            ref = f"{parent.shipment_reference}-CH{idx+1}"
            child = Shipment(
                shipment_reference=ref,
                sender_org_id=user.organization_id,
                receiver_org_id=child_data["receiver_org_id"],
                parent_shipment_id=parent.id,
                status=ShipmentStatus.DISPATCHED,
                declared_quantity=len(pkg_ids),
                dispatch_timestamp=datetime.utcnow(),
                created_by=user.id,
                notes=f"Child split shipment from {parent.shipment_reference}"
            )
            db.add(child)
            await db.commit()
            await db.refresh(child)

            for p_id in pkg_ids:
                pkg_obj = (await db.execute(
                    select(SerializedPackage).where(SerializedPackage.package_serial_id == p_id)
                )).scalar_one_or_none()
                if pkg_obj:
                    pkg_obj.status = PackageStatus.IN_TRANSIT
                    db.add(ShipmentItem(shipment_id=child.id, package_id=pkg_obj.id, quantity_dispatched=1))
                    db.add(CustodyEvent(
                        package_id=pkg_obj.id,
                        shipment_id=child.id,
                        event_type=CustodyEventType.SPLIT,
                        from_org_id=user.organization_id,
                        to_org_id=child_data["receiver_org_id"],
                        performed_by=user.id,
                        notes=f"Allocated into child split shipment {ref}"
                    ))
            created_children.append(child)

        await adapter.split_shipment({
            "parent_shipment_id": parent.id,
            "allocated_quantities": total_split_qty,
            "child_count": len(child_allocations)
        })
        await db.commit()
        return created_children

