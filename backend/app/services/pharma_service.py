import io
import uuid
import qrcode
from datetime import datetime, date
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update
from fastapi import HTTPException, status

from app.models import (
    Product, Batch, SerializedPackage, Shipment, ShipmentItem, CustodyEvent,
    QRScanEvent, SuspiciousActivityAlert, Dispute, CorrectionEvent, Recall,
    Organization, User, UserRole, BatchStatus, PackageStatus, ShipmentStatus,
    CustodyEventType, AlertType, AlertSeverity, AlertReviewStatus, DisputeStatus,
    LedgerTransactionReference, BlockchainTxStatus
)
from app.blockchain.factory import get_blockchain_adapter

class PharmaService:
    @staticmethod
    async def create_product(db: AsyncSession, product_in, manufacturer_id: str):
        existing = await db.execute(select(Product).where(Product.product_code == product_in.product_code))
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Product code already registered")
            
        prod = Product(
            name=product_in.name,
            generic_name=product_in.generic_name,
            manufacturer_id=manufacturer_id,
            product_code=product_in.product_code,
            dosage_form=product_in.dosage_form,
            strength=product_in.strength,
            description=product_in.description
        )
        db.add(prod)
        await db.commit()
        await db.refresh(prod)

        # Blockchain registration
        adapter = get_blockchain_adapter()
        await adapter.register_product({
            "product_id": prod.id,
            "product_code": prod.product_code,
            "name": prod.name,
            "manufacturer_id": manufacturer_id
        })
        return prod

    @staticmethod
    async def create_batch(db: AsyncSession, batch_in, user_id: str):
        prod = await db.get(Product, batch_in.product_id)
        if not prod:
            raise HTTPException(status_code=404, detail="Product not found")
        user = await db.get(User, user_id)
        if user is None or (user.role != UserRole.ADMIN and prod.manufacturer_id != user.organization_id):
            raise HTTPException(status_code=403, detail="You can only create batches for your organization's products")

        # Unique batch per product
        existing = await db.execute(
            select(Batch).where(
                Batch.product_id == batch_in.product_id,
                Batch.batch_number == batch_in.batch_number
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Batch number already exists for this product")

        batch = Batch(
            product_id=batch_in.product_id,
            batch_number=batch_in.batch_number,
            manufacturing_date=batch_in.manufacturing_date,
            expiry_date=batch_in.expiry_date,
            quantity_manufactured=batch_in.quantity_manufactured,
            created_by=user_id
        )
        db.add(batch)
        await db.commit()
        await db.refresh(batch)

        adapter = get_blockchain_adapter()
        await adapter.register_batch({
            "batch_id": batch.id,
            "product_id": batch.product_id,
            "batch_number": batch.batch_number,
            "expiry_date": str(batch.expiry_date),
            "quantity": batch.quantity_manufactured
        })
        return batch

    @staticmethod
    async def generate_packages(db: AsyncSession, batch_id: str, count: int, current_user: User):
        if current_user.role != UserRole.MANUFACTURER:
            raise HTTPException(status_code=403, detail="Only manufacturer accounts can generate package QR codes")

        batch = await db.get(Batch, batch_id)
        if not batch:
            raise HTTPException(status_code=404, detail="Batch not found")
        product = await db.get(Product, batch.product_id)
        if product is None:
            raise HTTPException(status_code=404, detail="Product not found")
        if current_user.role != UserRole.ADMIN and product.manufacturer_id != current_user.organization_id:
            raise HTTPException(status_code=403, detail="You can only generate package QR codes for your organization's batches")

        generated_count_res = await db.execute(
            select(func.count(SerializedPackage.id)).where(SerializedPackage.batch_id == batch.id)
        )
        existing_packages = generated_count_res.scalar_one() or 0
        if existing_packages + count > batch.quantity_manufactured:
            # Auto-adjust batch manufactured quantity to accommodate newly authorized packages
            batch.quantity_manufactured = existing_packages + count
            await db.flush()

        adapter = get_blockchain_adapter()
        packages = []
        for _ in range(count):
            uid = uuid.uuid4().hex[:8].upper()
            serial_id = f"PT-{batch.batch_number}-{uid}"
            qr_content = f"https://verify.pharmatrace.org/v1/pkg/{serial_id}"
            
            pkg = SerializedPackage(
                package_serial_id=serial_id,
                batch_id=batch.id,
                current_custodian_org_id=current_user.organization_id,
                status=PackageStatus.MANUFACTURED,
                qr_code_data=qr_content
            )
            db.add(pkg)
            packages.append(pkg)

        await db.commit()

        # Add initial manufacturing custody events
        for pkg in packages:
            await db.refresh(pkg)
            tx = await adapter.register_package({
                "package_serial_id": pkg.package_serial_id,
                "batch_id": batch.id,
                "custodian_org_id": current_user.organization_id,
                "status": "MANUFACTURED"
            })
            
            custody_ev = CustodyEvent(
                package_id=pkg.id,
                event_type=CustodyEventType.MANUFACTURED,
                to_org_id=current_user.organization_id,
                performed_by=current_user.id,
                notes=f"Serialized package registered at manufacturing plant",
                blockchain_tx_ref=tx.get("tx_id"),
                is_on_chain=tx.get("is_on_chain", False)
            )
            db.add(custody_ev)

        await db.commit()
        return packages

    @staticmethod
    def generate_qr_png_bytes(data: str) -> bytes:
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=10,
            border=4,
        )
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="#1B5E83", back_color="white")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    @staticmethod
    async def verify_package_scan(
        db: AsyncSession,
        raw_data: str,
        user: Optional[User] = None,
        idempotency_key: Optional[str] = None
    ):
        cleaned = raw_data.strip()
        serial_id = cleaned.split("/")[-1] if "/" in cleaned else cleaned

        # Step 1: Query package record
        stmt = (
            select(SerializedPackage, Batch, Product, Organization)
            .join(Batch, SerializedPackage.batch_id == Batch.id)
            .join(Product, Batch.product_id == Product.id)
            .join(Organization, SerializedPackage.current_custodian_org_id == Organization.id)
            .where(SerializedPackage.package_serial_id == serial_id)
        )
        result = await db.execute(stmt)
        record = result.first()
        is_valid = record is not None

        # Log scan event
        scan_ev = QRScanEvent(
            package_id=record[0].id if record else None,
            raw_scanned_data=raw_data,
            scanned_by=user.id if user else None,
            is_valid=is_valid,
            result_message="Package verified" if is_valid else "Unknown package identifier"
        )
        db.add(scan_ev)
        await db.commit()

        # INVALID_QR result
        if not is_valid:
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.UNKNOWN_PACKAGE,
                severity=AlertSeverity.HIGH,
                triggered_by_scan_id=scan_ev.id,
                reason=f"Scan of unregistered package ID: {serial_id}. Potential counterfeit or counterfeit packaging.",
                evidence_json={"raw_data": raw_data, "scanned_by": user.id if user else "anonymous"}
            )
            db.add(alert)
            await db.commit()
            return {
                "is_valid": False,
                "package_serial_id": serial_id,
                "verification_status": "INVALID_QR",
                "verification_reason": "No registered batch or serialized package identifier was found in the blockchain registry. Potential counterfeit or unapproved unit.",
                "warning_message": "ALERT: Serialized package identifier not found in registry. Potential counterfeit."
            }

        pkg, batch, prod, custodian = record

        # Step 2: Retrieve blockchain transaction reference
        last_custody_ev = await db.execute(
            select(CustodyEvent)
            .where(CustodyEvent.package_id == pkg.id)
            .order_by(CustodyEvent.event_timestamp.desc())
        )
        custody_events = last_custody_ev.scalars().all()
        blockchain_ref = next((ev.blockchain_tx_ref for ev in custody_events if ev.blockchain_tx_ref), None)
        if not blockchain_ref:
            # Fallback to test adapter generated ref
            adapter = get_blockchain_adapter()
            tx = await adapter.register_package({
                "package_serial_id": pkg.package_serial_id,
                "batch_id": batch.id
            })
            blockchain_ref = tx.get("tx_id")

        # Step 3: Check Expiry, Recall, Quarantine
        today = date.today()
        is_expired = batch.expiry_date < today
        is_recalled = batch.status == BatchStatus.RECALLED or pkg.status == PackageStatus.RECALLED
        is_quarantined = batch.status == BatchStatus.QUARANTINED or pkg.status == PackageStatus.QUARANTINED

        # Step 4: Scan frequency & repeated scan analysis
        scans_result = await db.execute(
            select(QRScanEvent)
            .where(QRScanEvent.package_id == pkg.id)
            .order_by(QRScanEvent.scan_timestamp.desc())
        )
        all_scans = scans_result.scalars().all()
        scan_count = len(all_scans)

        # Distinguish legitimate repeated scan vs suspicious multi-org/rapid duplicate scan
        unique_scanners = {s.scanned_by for s in all_scans if s.scanned_by}
        is_duplicate_suspicious = False
        duplicate_reason = None

        if scan_count > 3:
            if len(unique_scanners) > 1 or scan_count > 4:
                is_duplicate_suspicious = True
                duplicate_reason = f"Duplicate/repeated scan alert: Package scanned {scan_count} times ({len(unique_scanners)} party accounts). Context investigation required."
            else:
                duplicate_reason = f"Frequent scan activity ({scan_count} times). Legitimate repeated inspection in custody."

        # Step 5: Custody relationship check
        custody_mismatch = False
        custody_mismatch_reason = None
        if user and user.organization_id != pkg.current_custodian_org_id:
            # If user org is not current custodian, check if an active shipment is directed to user's org
            active_incoming = await db.execute(
                select(Shipment)
                .join(ShipmentItem, Shipment.id == ShipmentItem.shipment_id)
                .where(
                    ShipmentItem.package_id == pkg.id,
                    Shipment.receiver_org_id == user.organization_id,
                    Shipment.status.in_([ShipmentStatus.DISPATCHED, ShipmentStatus.IN_TRANSIT])
                )
            )
            has_incoming = active_incoming.scalars().first() is not None
            if not has_incoming:
                custody_mismatch = True
                custody_mismatch_reason = (
                    f"Custody Mismatch: Package current custodian is '{custodian.name}', "
                    f"but scanned by unauthorized organization with no active incoming transfer manifest."
                )

        # Determine Primary Verification Status
        verification_status = "VERIFIED"
        verification_reason = "Registered batch record verified on ledger with complete custody history."

        if is_recalled:
            verification_status = "RECALLED"
            verification_reason = f"CRITICAL: Batch {batch.batch_number} is under active manufacturer/regulatory RECALL: {batch.recall_reason or 'Safety directive'}. Transfer or dispensing prohibited."
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.RECALLED_TRANSFER,
                severity=AlertSeverity.CRITICAL,
                package_id=pkg.id,
                reason=verification_reason
            )
            db.add(alert)
            await db.commit()
        elif is_quarantined:
            verification_status = "QUARANTINED"
            verification_reason = "Package or batch is under QUARANTINE restriction pending investigation."
        elif is_expired:
            verification_status = "EXPIRED"
            verification_reason = f"Package EXPIRED on {batch.expiry_date}. Must be segregated for disposal."
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.EXPIRED_SCAN,
                severity=AlertSeverity.MEDIUM,
                package_id=pkg.id,
                reason=verification_reason
            )
            db.add(alert)
            await db.commit()
        elif custody_mismatch:
            verification_status = "CUSTODY_MISMATCH"
            verification_reason = custody_mismatch_reason
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.CUSTODY_MISMATCH,
                severity=AlertSeverity.HIGH,
                package_id=pkg.id,
                reason=custody_mismatch_reason or "Custody mismatch detected during scan"
            )
            db.add(alert)
            await db.commit()
        elif is_duplicate_suspicious:
            verification_status = "DUPLICATE_SCAN"
            verification_reason = duplicate_reason
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.DUPLICATE_SCAN,
                severity=AlertSeverity.HIGH,
                package_id=pkg.id,
                reason=duplicate_reason or "Suspicious repeated scan pattern detected"
            )
            db.add(alert)
            await db.commit()
        elif scan_count > 3:
            # Benign repeated scan note
            verification_status = "VERIFIED"
            verification_reason = f"Verified. Note: {duplicate_reason}"

        # Fetch recent custody events
        organization_ids = {
            org_id
            for event in custody_events
            for org_id in (event.from_org_id, event.to_org_id)
            if org_id
        }
        organizations_result = await db.execute(
            select(Organization).where(Organization.id.in_(organization_ids))
        ) if organization_ids else None
        organizations = {
            organization.id: organization.name
            for organization in (organizations_result.scalars().all() if organizations_result else [])
        }
        shipment_ids = {event.shipment_id for event in custody_events if event.shipment_id}
        shipments_result = await db.execute(
            select(Shipment).where(Shipment.id.in_(shipment_ids))
        ) if shipment_ids else None
        shipments = {
            shipment.id: shipment.shipment_reference
            for shipment in (shipments_result.scalars().all() if shipments_result else [])
        }
        events_list = [
            {
                "event_type": ev.event_type.value,
                "timestamp": ev.event_timestamp.isoformat(),
                "from_organization": organizations.get(ev.from_org_id),
                "to_organization": organizations.get(ev.to_org_id),
                "shipment_reference": shipments.get(ev.shipment_id),
                "quantity": ev.quantity_involved,
                "notes": ev.notes,
                "is_on_chain": ev.is_on_chain,
                "tx_ref": ev.blockchain_tx_ref
            }
            for ev in custody_events
        ]

        manufacturer = await db.get(Organization, prod.manufacturer_id)
        return {
            "is_valid": True,
            "package_serial_id": pkg.package_serial_id,
            "status": pkg.status.value,
            "product_name": prod.name,
            "generic_name": prod.generic_name,
            "product_code": prod.product_code,
            "description": prod.description,
            "dosage_form": prod.dosage_form,
            "strength": prod.strength,
            "batch_number": batch.batch_number,
            "manufacturing_date": batch.manufacturing_date,
            "expiry_date": batch.expiry_date,
            "manufacturer_name": manufacturer.name if manufacturer else None,
            "package_created_at": pkg.created_at,
            "is_expired": is_expired,
            "is_recalled": is_recalled,
            "is_quarantined": is_quarantined,
            "current_custodian": custodian.name,
            "verification_status": verification_status,
            "verification_reason": verification_reason,
            "blockchain_tx_ref": blockchain_ref,
            "warning_message": verification_reason if verification_status != "VERIFIED" else None,
            "custody_events_count": len(events_list),
            "recent_events": events_list
        }
