from datetime import date, datetime, time, timedelta
from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import or_, select

from app.db.session import get_db
from app.core.permissions import get_current_user
from app.models import (
    AlertReviewStatus, Batch, BatchStatus, CustodyEvent, Dispute, Organization, OrgType,
    PackageStatus, Product, QRScanEvent, Recall, RecallStatus, Shipment,
    ShipmentItem, ShipmentStatus, SerializedPackage, SuspiciousActivityAlert,
    User, UserRole,
)
from app.schemas import (
    ShipmentCreate, ShipmentDetailResponse, ShipmentResponse,
    ShipmentReceiveRequest, ShipmentSplitRequest
)
from app.services.custody_service import CustodyService

router = APIRouter(prefix="/shipments", tags=["Shipments & Custody Transfers"])


@router.get("/distributor-dashboard")
async def get_distributor_dashboard(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in (UserRole.DISTRIBUTOR, UserRole.PHARMACY_STAFF):
        raise HTTPException(
            status_code=403,
            detail="Only distributors and pharmacy staff can view this dashboard.",
        )

    organization_id = current_user.organization_id
    shipment_result = await db.execute(
        select(Shipment)
        .where(
            or_(
                Shipment.sender_org_id == organization_id,
                Shipment.receiver_org_id == organization_id,
            )
        )
        .order_by(Shipment.created_at.desc())
    )
    shipments_result = shipment_result.scalars().all()
    shipment_ids = [shipment.id for shipment in shipments_result]

    receiver_names: dict[str, str] = {}
    sender_names: dict[str, str] = {}
    organization_types: dict[str, str] = {}
    if shipment_ids:
        related_org_ids = {
            org_id
            for shipment in shipments_result
            for org_id in (shipment.sender_org_id, shipment.receiver_org_id)
        }
        organization_result = await db.execute(
            select(
                Organization.id,
                Organization.name,
                Organization.org_type,
            ).where(
                Organization.id.in_(related_org_ids)
            )
        )
        organization_rows = organization_result.all()
        names = {org_id: name for org_id, name, _ in organization_rows}
        organization_types = {
            org_id: org_type.value for org_id, _, org_type in organization_rows
        }
        sender_names = names
        receiver_names = names

    shipment_items_by_id: dict[str, list[dict]] = {}
    tx_refs_by_shipment: dict[str, str] = {}
    if shipment_ids:
        item_result = await db.execute(
            select(
                ShipmentItem.shipment_id,
                SerializedPackage.package_serial_id,
                SerializedPackage.status,
                Batch.id,
                Batch.batch_number,
                Product.name,
                ShipmentItem.quantity_dispatched,
                ShipmentItem.quantity_received,
                ShipmentItem.status,
            )
            .join(SerializedPackage, ShipmentItem.package_id == SerializedPackage.id)
            .join(Batch, SerializedPackage.batch_id == Batch.id)
            .join(Product, Batch.product_id == Product.id)
            .where(ShipmentItem.shipment_id.in_(shipment_ids))
            .order_by(SerializedPackage.package_serial_id)
        )
        for (
            shipment_id,
            serial_id,
            package_status,
            batch_id,
            batch_number,
            product_name,
            quantity_dispatched,
            quantity_received,
            item_status,
        ) in item_result.all():
            shipment_items_by_id.setdefault(shipment_id, []).append(
                {
                    "package_serial_id": serial_id,
                    "batch_id": batch_id,
                    "package_status": package_status.value,
                    "batch_number": batch_number,
                    "product_name": product_name,
                    "quantity_dispatched": quantity_dispatched,
                    "quantity_received": quantity_received,
                    "status": item_status,
                }
            )

        event_result = await db.execute(
            select(CustodyEvent.shipment_id, CustodyEvent.blockchain_tx_ref)
            .where(
                CustodyEvent.shipment_id.in_(shipment_ids),
                CustodyEvent.blockchain_tx_ref.is_not(None),
            )
            .order_by(CustodyEvent.event_timestamp.desc())
        )
        for shipment_id, tx_ref in event_result.all():
            tx_refs_by_shipment.setdefault(shipment_id, tx_ref)

    shipments = [
        {
            "id": shipment.id,
            "shipment_reference": shipment.shipment_reference,
            "sender_org_id": shipment.sender_org_id,
            "sender_organization_name": sender_names.get(shipment.sender_org_id),
            "sender_org_type": organization_types.get(shipment.sender_org_id),
            "receiver_org_id": shipment.receiver_org_id,
            "receiver_organization_name": receiver_names.get(
                shipment.receiver_org_id
            ),
            "receiver_org_type": organization_types.get(shipment.receiver_org_id),
            "status": shipment.status.value,
            "declared_quantity": shipment.declared_quantity,
            "received_quantity": shipment.received_quantity,
            "dispatch_timestamp": shipment.dispatch_timestamp,
            "receipt_timestamp": shipment.receipt_timestamp,
            "created_at": shipment.created_at,
            "notes": shipment.notes,
            "items": shipment_items_by_id.get(shipment.id, []),
            "blockchain_tx_ref": tx_refs_by_shipment.get(shipment.id),
        }
        for shipment in shipments_result
    ]

    inventory_result = await db.execute(
        select(SerializedPackage, Batch, Product, Organization)
        .join(Batch, SerializedPackage.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
        .join(Organization, Product.manufacturer_id == Organization.id)
        .where(SerializedPackage.current_custodian_org_id == organization_id)
        .order_by(Product.name, Batch.batch_number, SerializedPackage.package_serial_id)
    )
    inventory_rows = inventory_result.all()
    inventory = [
        {
            "id": package.id,
            "package_serial_id": package.package_serial_id,
            "batch_id": batch.id,
            "batch_number": batch.batch_number,
            "product_name": product.name,
            "manufacturer_name": manufacturer.name,
            "manufacturing_date": batch.manufacturing_date,
            "expiry_date": batch.expiry_date,
            "batch_status": batch.status.value,
            "status": package.status.value,
        }
        for package, batch, product, manufacturer in inventory_rows
    ]
    inventory_batch_ids = {batch.id for _, batch, _, _ in inventory_rows}

    recalls: list[dict] = []
    if inventory_batch_ids:
        recall_result = await db.execute(
            select(Recall, Batch.batch_number, Product.name)
            .join(Batch, Recall.batch_id == Batch.id)
            .join(Product, Batch.product_id == Product.id)
            .where(Recall.batch_id.in_(inventory_batch_ids))
            .order_by(Recall.created_at.desc())
        )
        recalls = [
            {
                "id": recall.id,
                "batch_id": recall.batch_id,
                "batch_number": batch_number,
                "product_name": product_name,
                "recall_reason": recall.recall_reason,
                "severity": recall.severity.value,
                "status": recall.status.value,
                "created_at": recall.created_at,
            }
            for recall, batch_number, product_name in recall_result.all()
        ]

    inventory_package_ids = {package.id for package, _, _, _ in inventory_rows}
    org_user_result = await db.execute(
        select(User.id).where(User.organization_id == organization_id)
    )
    org_user_ids = [user_id for (user_id,) in org_user_result.all()]

    alert_filters = []
    if shipment_ids:
        alert_filters.append(SuspiciousActivityAlert.shipment_id.in_(shipment_ids))
    if inventory_package_ids:
        alert_filters.append(
            SuspiciousActivityAlert.package_id.in_(inventory_package_ids)
        )
    if org_user_ids:
        scan_ids = select(QRScanEvent.id).where(
            QRScanEvent.scanned_by.in_(org_user_ids)
        )
        alert_filters.append(
            SuspiciousActivityAlert.triggered_by_scan_id.in_(scan_ids)
        )
    alerts: list[dict] = []
    if alert_filters:
        alerts_result = await db.execute(
            select(SuspiciousActivityAlert)
            .where(or_(*alert_filters))
            .order_by(SuspiciousActivityAlert.created_at.desc())
            .limit(200)
        )
        alerts = [
            {
                "id": alert.id,
                "alert_type": alert.alert_type.value,
                "severity": alert.severity.value,
                "shipment_id": alert.shipment_id,
                "reason": alert.reason,
                "review_status": alert.review_status.value,
                "created_at": alert.created_at,
            }
            for alert in alerts_result.scalars().all()
        ]

    related_shipment_ids = set(shipment_ids)
    disputes: list[dict] = []
    if related_shipment_ids:
        dispute_result = await db.execute(
            select(Dispute, Shipment.shipment_reference)
            .join(Shipment, Dispute.shipment_id == Shipment.id)
            .where(Dispute.shipment_id.in_(related_shipment_ids))
            .order_by(Dispute.created_at.desc())
        )
        disputes = [
            {
                "id": dispute.id,
                "shipment_id": dispute.shipment_id,
                "shipment_reference": shipment_reference,
                "dispute_reason": dispute.dispute_reason,
                "expected_quantity": dispute.expected_quantity,
                "actual_quantity": dispute.actual_quantity,
                "status": dispute.status.value,
                "created_at": dispute.created_at,
            }
            for dispute, shipment_reference in dispute_result.all()
        ]

    expiry_alerts = [
        {
            "type": "expiry",
            "title": "Batch approaching expiry",
            "message": (
                f"{item['product_name']}, batch {item['batch_number']}, "
                f"expires {item['expiry_date']}."
            ),
            "created_at": item["expiry_date"],
        }
        for item in inventory
        if item["status"] == PackageStatus.RECEIVED.value
        and item["batch_status"] != "recalled"
        and item["expiry_date"] <= date.today() + timedelta(days=30)
        and item["expiry_date"] >= date.today()
    ]
    expiry_alerts = [
        {
            **alert,
            "created_at": datetime.combine(alert["created_at"], time.min),
        }
        for alert in expiry_alerts
    ]
    notifications = [
        {
            "type": "incoming_shipment",
            "title": "Incoming shipment awaiting receipt",
            "message": (
                f"{shipment['shipment_reference']} from "
                f"{shipment['sender_organization_name']} is awaiting receipt."
            ),
            "created_at": shipment["dispatch_timestamp"],
        }
        for shipment in shipments
        if shipment["receiver_org_id"] == organization_id
        and shipment["status"] in (
            ShipmentStatus.DISPATCHED.value,
            ShipmentStatus.IN_TRANSIT.value,
        )
    ]
    notifications.extend(
        {
            "type": "dispute",
            "title": "Shipment receipt dispute",
            "message": (
                f"{dispute['shipment_reference']}: {dispute['dispute_reason']}"
            ),
            "created_at": dispute["created_at"],
        }
        for dispute in disputes
        if dispute["status"] == "open"
    )
    notifications.extend(
        {
            "type": "suspicious_scan",
            "title": f"Suspicious activity · {alert['severity']}",
            "message": alert["reason"],
            "created_at": alert["created_at"],
        }
        for alert in alerts
        if alert["review_status"] == AlertReviewStatus.OPEN.value
    )
    notifications.extend(expiry_alerts)
    notifications.extend(
        {
            "type": "recall",
            "title": f"Recall · batch {recall['batch_number']}",
            "message": recall["recall_reason"],
            "created_at": recall["created_at"],
        }
        for recall in recalls
        if recall["status"] == RecallStatus.ACTIVE.value
    )

    incoming = [
        shipment for shipment in shipments
        if shipment["receiver_org_id"] == organization_id
    ]
    outgoing = [
        shipment for shipment in shipments
        if shipment["sender_org_id"] == organization_id
    ]
    pharmacy_ids_result = await db.execute(
        select(Organization.id).where(Organization.org_type == OrgType.PHARMACY)
    )
    pharmacy_ids = {org_id for (org_id,) in pharmacy_ids_result.all()}
    stored_batch_ids = {
        item["batch_id"]
        for item in inventory
        if item["status"] == PackageStatus.RECEIVED.value
    }
    summary = {
        "incoming_shipments": sum(
            shipment["status"] in (
                ShipmentStatus.DISPATCHED.value,
                ShipmentStatus.IN_TRANSIT.value,
            )
            for shipment in incoming
        ),
        "received_batches": len({
            item["batch_id"]
            for shipment in incoming
            if shipment["status"] in (
                ShipmentStatus.RECEIVED.value,
                ShipmentStatus.PARTIALLY_RECEIVED.value,
            )
            for item in shipment["items"]
            if item["status"] == "received"
        }),
        "batches_in_storage": len(stored_batch_ids),
        "outgoing_shipments": len(outgoing),
        "open_alerts": sum(
            alert["review_status"] == AlertReviewStatus.OPEN.value
            for alert in alerts
        ),
        "pending_pharmacy_receipts": sum(
            shipment["sender_org_id"] == organization_id
            and shipment["receiver_org_id"] in pharmacy_ids
            and shipment["status"] in (
                ShipmentStatus.DISPATCHED.value,
                ShipmentStatus.IN_TRANSIT.value,
            )
            for shipment in shipments
        ),
    }
    return {
        "organization_id": organization_id,
        "summary": summary,
        "shipments": shipments,
        "incoming_shipments": [
            shipment for shipment in incoming
            if shipment["status"] in (
                ShipmentStatus.DISPATCHED.value,
                ShipmentStatus.IN_TRANSIT.value,
            )
        ],
        "outgoing_shipments": outgoing,
        "inventory": inventory,
        "recalls": recalls,
        "alerts": alerts,
        "disputes": disputes,
        "notifications": sorted(
            notifications,
            key=lambda item: item["created_at"] or datetime.min,
            reverse=True,
        ),
    }


@router.get("/inventory")
async def list_transfer_inventory(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in (UserRole.DISTRIBUTOR, UserRole.PHARMACY_STAFF):
        raise HTTPException(
            status_code=403,
            detail="Only distributors and pharmacy staff can view transfer inventory.",
        )
    result = await db.execute(
        select(SerializedPackage, Batch, Product)
        .join(Batch, SerializedPackage.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
        .where(
            SerializedPackage.current_custodian_org_id == current_user.organization_id,
            SerializedPackage.status.in_(
                [PackageStatus.MANUFACTURED, PackageStatus.RECEIVED]
            ),
        )
        .order_by(Product.name, Batch.batch_number, SerializedPackage.package_serial_id)
    )
    return [
        {
            "package_serial_id": package.package_serial_id,
            "product_name": product.name,
            "batch_number": batch.batch_number,
            "status": package.status.value,
        }
        for package, batch, product in result.all()
    ]

@router.post("", response_model=ShipmentResponse)
async def create_shipment(
    payload: ShipmentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    receiver = await db.get(Organization, payload.receiver_org_id)
    if not receiver or not receiver.is_active:
        raise HTTPException(status_code=404, detail="Active receiver organization not found")
    if current_user.role == UserRole.DISTRIBUTOR and receiver.org_type not in (
        OrgType.DISTRIBUTOR,
        OrgType.PHARMACY,
    ):
        raise HTTPException(
            status_code=400,
            detail="Distributor transfers must be addressed to a distributor or pharmacy organization.",
        )
    return await CustodyService.create_and_dispatch_shipment(
        db,
        sender=current_user,
        receiver_org_id=payload.receiver_org_id,
        package_serial_ids=payload.package_serial_ids,
        transporter_org_id=payload.transporter_org_id,
        notes=payload.notes
    )

@router.get("", response_model=List[ShipmentResponse])
async def list_shipments(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Shipment).where(
        (Shipment.sender_org_id == current_user.organization_id) |
        (Shipment.receiver_org_id == current_user.organization_id)
    ).order_by(Shipment.created_at.desc())
    result = await db.execute(stmt)
    return result.scalars().all()

@router.get("/{shipment_id}", response_model=ShipmentDetailResponse)
async def get_shipment(
    shipment_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    shipment = await db.get(Shipment, shipment_id)
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    if (
        current_user.role != UserRole.ADMIN
        and current_user.organization_id
        not in (shipment.sender_org_id, shipment.receiver_org_id)
    ):
        raise HTTPException(status_code=403, detail="You cannot view this shipment")

    sender = await db.get(Organization, shipment.sender_org_id)
    receiver = await db.get(Organization, shipment.receiver_org_id)
    items_result = await db.execute(
        select(ShipmentItem, SerializedPackage)
        .join(SerializedPackage, ShipmentItem.package_id == SerializedPackage.id)
        .where(ShipmentItem.shipment_id == shipment.id)
        .order_by(SerializedPackage.package_serial_id)
    )
    disputes_result = await db.execute(
        select(Dispute)
        .where(Dispute.shipment_id == shipment.id)
        .order_by(Dispute.created_at)
    )

    return {
        **ShipmentResponse.model_validate(shipment).model_dump(),
        "sender_organization_name": sender.name if sender else "Unknown organization",
        "receiver_organization_name": receiver.name if receiver else "Unknown organization",
        "items": [
            {
                "package_serial_id": package.package_serial_id,
                "quantity_dispatched": item.quantity_dispatched,
                "quantity_received": item.quantity_received,
                "status": item.status,
            }
            for item, package in items_result.all()
        ],
        "disputes": disputes_result.scalars().all(),
    }

@router.post("/{shipment_id}/receive")
async def receive_shipment(
    shipment_id: str,
    payload: ShipmentReceiveRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Two-Party Custody Verification:
    Recipient independently confirms actual quantity received.
    Triggers dispute and flags anomalies if quantities mismatch.
    """
    result = await CustodyService.process_shipment_receipt(
        db,
        shipment_id=shipment_id,
        receiver=current_user,
        actual_quantity_received=payload.actual_quantity_received,
        scanned_serial_ids=payload.scanned_package_serial_ids,
        notes=payload.notes
    )
    return {
        "status": "success",
        "shipment_id": result["shipment"].id,
        "shipment_status": result["shipment"].status.value,
        "declared_quantity": result["shipment"].declared_quantity,
        "received_quantity": result["shipment"].received_quantity,
        "discrepancy_detected": result["discrepancy"],
        "dispute_id": result["dispute_id"],
        "tx_reference": result["tx_reference"]
    }

@router.post("/{shipment_id}/split", response_model=List[ShipmentResponse])
async def split_shipment(
    shipment_id: str,
    payload: ShipmentSplitRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Split inventory into child shipments and reconcile quantities.
    Ensures sum(children) <= received quantity.
    """
    return await CustodyService.split_shipment(
        db,
        parent_shipment_id=shipment_id,
        user=current_user,
        child_allocations=payload.child_shipments
    )


@router.post("/dispense")
async def dispense_package(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Pharmacy Dispensing Record:
    Records package as dispensed to patient, marks status on ledger, and records custody event.
    """
    if current_user.role != UserRole.PHARMACY_STAFF:
        raise HTTPException(
            status_code=403,
            detail="Only pharmacy staff can record dispensing.",
        )
    package_serial_id = payload.get("package_serial_id", "").strip()
    patient_reference = payload.get("patient_reference", "").strip()
    notes = payload.get("notes", "").strip()
    if not package_serial_id:
        raise HTTPException(status_code=400, detail="Package serial ID is required.")

    result = await db.execute(
        select(SerializedPackage, Batch, Product)
        .join(Batch, SerializedPackage.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
        .where(SerializedPackage.package_serial_id == package_serial_id)
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Package not found.")
    package, batch, product = row

    if package.current_custodian_org_id != current_user.organization_id:
        raise HTTPException(status_code=403, detail="Package is not in this pharmacy's custody.")
    if package.status == PackageStatus.DISPENSED:
        raise HTTPException(status_code=400, detail="Package has already been dispensed.")
    if batch.status == BatchStatus.RECALLED or package.status == PackageStatus.RECALLED:
        raise HTTPException(status_code=400, detail="Cannot dispense a recalled batch/package.")
    if batch.expiry_date < date.today():
        raise HTTPException(status_code=400, detail="Cannot dispense an expired package.")

    package.status = PackageStatus.DISPENSED
    custody_event = CustodyEvent(
        package_id=package.id,
        event_type="dispensed",
        from_org_id=current_user.organization_id,
        performed_by=current_user.id,
        event_timestamp=datetime.utcnow(),
        notes=f"Dispensed. Patient Ref: {patient_reference}. Notes: {notes}".strip(),
        is_on_chain=True,
    )
    db.add(custody_event)
    await db.commit()
    return {
        "status": "success",
        "package_serial_id": package.package_serial_id,
        "product_name": product.name,
        "batch_number": batch.batch_number,
        "dispensed_at": custody_event.event_timestamp.isoformat(),
        "notes": custody_event.notes,
    }


@router.post("/sync-offline-receipts")
async def sync_offline_receipts(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Feature D: Offline-First Receipt Capture Synchronization.
    Re-validates authorization, shipment state, batch recall status,
    and idempotency before submitting authorized blockchain transaction.
    """
    receipts = payload.get("receipts", [])
    results = []

    for item in receipts:
        event_id = item.get("event_id") or item.get("idempotency_key")
        shipment_id = item.get("shipment_id")
        actual_qty = int(item.get("actual_quantity_received", 0))
        scanned_serials = item.get("scanned_package_serial_ids", [])
        notes = item.get("notes")
        device_timestamp = item.get("device_timestamp")

        shipment = await db.get(Shipment, shipment_id)
        if not shipment:
            results.append({
                "event_id": event_id,
                "shipment_id": shipment_id,
                "status": "FAILED",
                "error": "Shipment not found on the server registry.",
                "requires_manual_review": False
            })
            continue

        # Check for already processed / duplicate submission (idempotency)
        if shipment.status in (ShipmentStatus.RECEIVED, ShipmentStatus.PARTIALLY_RECEIVED, ShipmentStatus.REJECTED):
            results.append({
                "event_id": event_id,
                "shipment_id": shipment_id,
                "status": "ALREADY_PROCESSED",
                "message": f"Shipment receipt was already recorded with status: {shipment.status.value}",
                "requires_manual_review": False
            })
            continue

        # Re-validate recipient organization
        if shipment.receiver_org_id != current_user.organization_id:
            results.append({
                "event_id": event_id,
                "shipment_id": shipment_id,
                "status": "CONFLICT",
                "error": "Unauthorized recipient organization.",
                "requires_manual_review": True
            })
            continue

        # Re-validate batch recall status while device was offline
        # If any package was recalled while offline, flag for review!
        batch_items = await db.execute(
            select(Batch.status)
            .join(SerializedPackage, Batch.id == SerializedPackage.batch_id)
            .join(ShipmentItem, SerializedPackage.id == ShipmentItem.package_id)
            .where(ShipmentItem.shipment_id == shipment.id)
        )
        batch_statuses = [s for (s,) in batch_items.all()]
        if any(bs == BatchStatus.RECALLED for bs in batch_statuses):
            results.append({
                "event_id": event_id,
                "shipment_id": shipment_id,
                "status": "CONFLICT",
                "error": "CRITICAL CONFLICT: A batch in this shipment was RECALLED while offline. Transfer restricted.",
                "requires_manual_review": True
            })
            continue

        # Process valid receipt through CustodyService
        try:
            res = await CustodyService.process_shipment_receipt(
                db,
                shipment_id=shipment_id,
                receiver=current_user,
                actual_quantity_received=actual_qty,
                scanned_serial_ids=scanned_serials if scanned_serials else None,
                notes=f"[Offline Sync - captured at {device_timestamp or 'device'}] {notes or ''}".strip()
            )
            results.append({
                "event_id": event_id,
                "shipment_id": shipment_id,
                "status": "SYNCHRONIZED",
                "blockchain_tx_ref": res.get("tx_reference"),
                "discrepancy_detected": res.get("discrepancy"),
                "requires_manual_review": False
            })
        except Exception as ex:
            results.append({
                "event_id": event_id,
                "shipment_id": shipment_id,
                "status": "FAILED",
                "error": str(ex),
                "requires_manual_review": True
            })

    return {"synced_count": sum(1 for r in results if r["status"] == "SYNCHRONIZED"), "results": results}
