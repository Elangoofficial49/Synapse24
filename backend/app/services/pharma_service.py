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

        generated_count = await db.execute(
            select(func.count(SerializedPackage.id)).where(SerializedPackage.batch_id == batch.id)
        )
        if generated_count.scalar_one() + count > batch.quantity_manufactured:
            raise HTTPException(
                status_code=400,
                detail="Package count cannot exceed the batch's manufactured quantity",
            )

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
    async def verify_package_scan(db: AsyncSession, raw_data: str, user: Optional[User] = None):
        cleaned = raw_data.strip()
        serial_id = cleaned.split("/")[-1] if "/" in cleaned else cleaned
        
        # Check package
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
        scan_ev = QRScanEvent(
            package_id=record[0].id if record else None,
            raw_scanned_data=raw_data,
            scanned_by=user.id if user else None,
            is_valid=is_valid,
            result_message="Package verified successfully" if is_valid else "Unknown package serialized identifier"
        )
        db.add(scan_ev)
        await db.commit()

        if not is_valid:
            # Raise suspicious alert
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.UNKNOWN_PACKAGE,
                severity=AlertSeverity.HIGH,
                triggered_by_scan_id=scan_ev.id,
                reason=f"Scan of unverified or unregistered package ID: {serial_id}",
                evidence_json={"raw_data": raw_data, "scanned_by": user.id if user else "anonymous"}
            )
            db.add(alert)
            await db.commit()
            return {
                "is_valid": False,
                "package_serial_id": serial_id,
                "warning_message": "ALERT: Serialized package identifier not found in registry. Potential counterfeit or unregistered unit."
            }

        pkg, batch, prod, custodian = record
        
        # Anomaly Detection Checks
        today = date.today()
        is_expired = batch.expiry_date < today
        is_recalled = batch.status == BatchStatus.RECALLED or pkg.status == PackageStatus.RECALLED
        is_quarantined = batch.status == BatchStatus.QUARANTINED or pkg.status == PackageStatus.QUARANTINED

        # Detect multiple rapid scans or unexpected sequence
        recent_scans = await db.execute(
            select(func.count(QRScanEvent.id))
            .where(QRScanEvent.package_id == pkg.id)
        )
        scan_count = recent_scans.scalar_one()

        if is_expired:
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.EXPIRED_SCAN,
                severity=AlertSeverity.MEDIUM,
                package_id=pkg.id,
                reason=f"Scan of expired medicine package (Expiry: {batch.expiry_date})"
            )
            db.add(alert)
            await db.commit()

        if is_recalled:
            alert = SuspiciousActivityAlert(
                alert_type=AlertType.RECALLED_TRANSFER,
                severity=AlertSeverity.CRITICAL,
                package_id=pkg.id,
                reason=f"Scan of active recalled batch package (Batch: {batch.batch_number})"
            )
            db.add(alert)
            await db.commit()

        # Fetch recent custody events
        cust_events = await db.execute(
            select(CustodyEvent).where(CustodyEvent.package_id == pkg.id).order_by(CustodyEvent.event_timestamp.desc())
        )
        custody_events = cust_events.scalars().all()
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

        warning = None
        if is_recalled:
            warning = "CRITICAL WARNING: This batch has been RECALLED. Do not dispense or transfer!"
        elif is_quarantined:
            warning = "WARNING: This package is under QUARANTINE."
        elif is_expired:
            warning = "WARNING: Product has EXPIRED. Do not distribute or consume."

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
            "warning_message": warning,
            "custody_events_count": len(events_list),
            "recent_events": events_list
        }
