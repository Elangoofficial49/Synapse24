from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.permissions import get_current_user, require_roles
from app.db.session import get_db
from app.models import (
    AlertReviewStatus,
    Batch,
    BatchDocument,
    BatchStatus,
    CustodyEvent,
    CustodyEventType,
    Dispute,
    Organization,
    OrgType,
    PackageStatus,
    Product,
    Recall,
    RecallSeverity,
    RecallStatus,
    SerializedPackage,
    Shipment,
    ShipmentItem,
    ShipmentStatus,
    SuspiciousActivityAlert,
    User,
    UserRole,
)
from app.schemas import RecallCreate, RecallResponse
from app.services.recall_service import RecallService

router = APIRouter(prefix="/manufacturer", tags=["Manufacturer Dashboard"])

MANUFACTURER_ROLES = [UserRole.MANUFACTURER]
ALLOWED_DOCUMENT_TYPES = {
    ".pdf": ("application/pdf", b"%PDF-"),
    ".png": ("image/png", b"\x89PNG\r\n\x1a\n"),
    ".jpg": ("image/jpeg", b"\xff\xd8\xff"),
    ".jpeg": ("image/jpeg", b"\xff\xd8\xff"),
}


def _document_root() -> Path:
    root = Path(settings.DOCUMENT_STORAGE_PATH)
    if not root.is_absolute():
        root = Path.cwd() / root
    return root.resolve()


@router.get("/dashboard")
async def get_manufacturer_dashboard(
    current_user: User = Depends(require_roles(MANUFACTURER_ROLES)),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    organization_id = current_user.organization_id
    batches_result = await db.execute(
        select(Batch, Product)
        .join(Product, Batch.product_id == Product.id)
        .where(Product.manufacturer_id == organization_id)
        .order_by(Batch.created_at.desc())
    )
    batch_records = batches_result.all()
    batch_ids = [batch.id for batch, _ in batch_records]
    batch_id_set = set(batch_ids)

    package_counts: dict[str, dict[str, int]] = {}
    if batch_ids:
        package_result = await db.execute(
            select(SerializedPackage.batch_id, SerializedPackage.status, func.count())
            .where(SerializedPackage.batch_id.in_(batch_ids))
            .group_by(SerializedPackage.batch_id, SerializedPackage.status)
        )
        for batch_id, status, count in package_result.all():
            package_counts.setdefault(batch_id, {})[status.value] = count

    shipment_result = await db.execute(
        select(Shipment, Organization.name)
        .join(Organization, Shipment.receiver_org_id == Organization.id)
        .where(
            Shipment.sender_org_id == organization_id,
            Shipment.status.in_(
                [ShipmentStatus.DISPATCHED, ShipmentStatus.IN_TRANSIT]
            ),
        )
        .order_by(Shipment.dispatch_timestamp.desc())
    )
    pending_receipts = [
        {
            "id": shipment.id,
            "shipment_reference": shipment.shipment_reference,
            "receiver_organization_name": receiver_name,
            "status": shipment.status.value,
            "declared_quantity": shipment.declared_quantity,
            "dispatch_timestamp": shipment.dispatch_timestamp,
            "notes": shipment.notes,
        }
        for shipment, receiver_name in shipment_result.all()
    ]

    distributor_result = await db.execute(
        select(Organization)
        .where(
            Organization.org_type == OrgType.DISTRIBUTOR,
        )
        .order_by(Organization.name)
    )
    distributors = [
        {
            "id": organization.id,
            "name": organization.name,
            "license_number": organization.license_number,
            "address": organization.address,
            "contact_email": organization.contact_email,
            "is_verified": organization.is_active,
        }
        for organization in distributor_result.scalars().all()
    ]

    recall_result = await db.execute(
        select(Recall, Batch.batch_number)
        .join(Batch, Recall.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
        .where(Product.manufacturer_id == organization_id)
        .order_by(Recall.created_at.desc())
    )
    recalls = [
        {
            "id": recall.id,
            "batch_id": recall.batch_id,
            "batch_number": batch_number,
            "recall_reason": recall.recall_reason,
            "severity": recall.severity.value,
            "affected_package_count": recall.affected_package_count,
            "status": recall.status.value,
            "created_at": recall.created_at,
        }
        for recall, batch_number in recall_result.all()
    ]

    audit_history: list[dict[str, Any]] = []
    audit_history.extend(
        {
            "event_type": "recall",
            "entity_id": recall["id"],
            "batch_number": recall["batch_number"],
            "description": f"Batch {recall['batch_number']} recalled",
            "notes": recall["recall_reason"],
            "occurred_at": recall["created_at"],
        }
        for recall in recalls
    )
    if batch_ids:
        for batch, product in batch_records:
            audit_history.append({
                "event_type": "batch_created",
                "entity_id": batch.id,
                "batch_number": batch.batch_number,
                "product_name": product.name,
                "description": f"Batch {batch.batch_number} registered",
                "occurred_at": batch.created_at,
            })

        event_result = await db.execute(
            select(
                CustodyEvent,
                SerializedPackage.package_serial_id,
                Batch.batch_number,
            )
            .join(SerializedPackage, CustodyEvent.package_id == SerializedPackage.id)
            .join(Batch, SerializedPackage.batch_id == Batch.id)
            .join(Product, Batch.product_id == Product.id)
            .where(Product.manufacturer_id == organization_id)
            .order_by(CustodyEvent.event_timestamp.desc())
            .limit(500)
        )
        event_labels = {
            CustodyEventType.DISPATCHED: "Package dispatched",
            CustodyEventType.RECEIVED: "Receipt confirmed",
            CustodyEventType.PARTIALLY_RECEIVED: "Partial receipt confirmed",
            CustodyEventType.REJECTED: "Shipment rejected",
            CustodyEventType.RECALLED: "Package recalled",
            CustodyEventType.MANUFACTURED: "Package QR registered",
        }
        for event, package_serial, batch_number in event_result.all():
            audit_history.append({
                "event_type": event.event_type.value,
                "entity_id": event.shipment_id or event.package_id,
                "batch_number": batch_number,
                "description": (
                    f"{event_labels.get(event.event_type, event.event_type.value)}: "
                    f"{package_serial}"
                ),
                "notes": event.notes,
                "blockchain_tx_ref": event.blockchain_tx_ref,
                "occurred_at": event.event_timestamp,
            })

    document_result = await db.execute(
        select(BatchDocument, Batch.batch_number)
        .join(Batch, BatchDocument.batch_id == Batch.id)
        .where(BatchDocument.organization_id == organization_id)
        .order_by(BatchDocument.created_at.desc())
    )
    document_records = document_result.all()
    documents = [
        {
            "id": document.id,
            "batch_id": document.batch_id,
            "batch_number": batch_number,
            "original_filename": document.original_filename,
            "content_type": document.content_type,
            "file_size": document.file_size,
            "created_at": document.created_at,
        }
        for document, batch_number in document_records
    ]
    audit_history.extend(
        {
            "event_type": "document_uploaded",
            "entity_id": document.id,
            "batch_number": batch_number,
            "description": f"Document uploaded: {document.original_filename}",
            "occurred_at": document.created_at,
        }
        for document, batch_number in document_records
    )

    notifications: list[dict[str, Any]] = [
        {
            "type": "pending_receipt",
            "title": "Delivery awaiting confirmation",
            "message": (
                f"{shipment['shipment_reference']} to "
                f"{shipment['receiver_organization_name']} is awaiting receipt."
            ),
            "entity_id": shipment["id"],
            "created_at": shipment["dispatch_timestamp"],
        }
        for shipment in pending_receipts
    ]
    if batch_ids:
        package_ids_query = select(SerializedPackage.id).where(
            SerializedPackage.batch_id.in_(batch_ids)
        )
        alerts_result = await db.execute(
            select(SuspiciousActivityAlert)
            .where(
                (SuspiciousActivityAlert.package_id.in_(package_ids_query))
                | (
                    SuspiciousActivityAlert.shipment_id.in_(
                        select(Shipment.id).where(
                            Shipment.sender_org_id == organization_id
                        )
                    )
                )
            )
            .order_by(SuspiciousActivityAlert.created_at.desc())
            .limit(100)
        )
        notifications.extend(
            {
                "type": "suspicious_scan",
                "title": f"Suspicious activity · {alert.severity.value}",
                "message": alert.reason,
                "entity_id": alert.id,
                "created_at": alert.created_at,
            }
            for alert in alerts_result.scalars().all()
            if alert.review_status == AlertReviewStatus.OPEN
        )
    expiring_batches = [
        (batch, product)
        for batch, product in batch_records
        if batch.status != BatchStatus.RECALLED
        and batch.expiry_date <= date.today() + timedelta(days=30)
        and batch.expiry_date >= date.today()
    ]
    notifications.extend(
        {
            "type": "expiry",
            "title": "Batch approaching expiry",
            "message": f"{product.name}, batch {batch.batch_number}, expires {batch.expiry_date}.",
            "entity_id": batch.id,
            "created_at": datetime.combine(batch.expiry_date, datetime.min.time()),
        }
        for batch, product in expiring_batches
    )
    notifications.extend(
        {
            "type": "recall",
            "title": "Active batch recall",
            "message": f"Batch {recall['batch_number']}: {recall['recall_reason']}",
            "entity_id": recall["id"],
            "created_at": recall["created_at"],
        }
        for recall in recalls
        if recall["status"] == RecallStatus.ACTIVE.value
    )

    batch_counts: dict[str, int] = {}
    for batch, _ in batch_records:
        batch_counts[batch.status.value] = batch_counts.get(batch.status.value, 0) + 1
    shipment_batch_count = (
        select(func.count(func.distinct(Batch.id)))
        .select_from(Shipment)
        .join(ShipmentItem, ShipmentItem.shipment_id == Shipment.id)
        .join(SerializedPackage, ShipmentItem.package_id == SerializedPackage.id)
        .join(Batch, SerializedPackage.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
        .where(
            Shipment.sender_org_id == organization_id,
            Product.manufacturer_id == organization_id,
        )
    )
    dispatched_count_result = await db.execute(
        shipment_batch_count.where(Shipment.status != ShipmentStatus.DRAFT)
    )
    in_transit_count_result = await db.execute(
        shipment_batch_count.where(
            Shipment.status.in_(
                [ShipmentStatus.DISPATCHED, ShipmentStatus.IN_TRANSIT]
            )
        )
    )

    inventory = [
        {
            "id": batch.id,
            "product_id": product.id,
            "product_name": product.name,
            "generic_name": product.generic_name,
            "batch_number": batch.batch_number,
            "manufacturing_date": batch.manufacturing_date,
            "expiry_date": batch.expiry_date,
            "quantity_manufactured": batch.quantity_manufactured,
            "status": batch.status.value,
            "package_counts": package_counts.get(batch.id, {}),
        }
        for batch, product in batch_records
    ]
    manufacturer = await db.get(Organization, organization_id)

    return {
        "manufacturer": {
            "id": manufacturer.id,
            "name": manufacturer.name,
            "license_number": manufacturer.license_number,
            "address": manufacturer.address,
            "contact_email": manufacturer.contact_email,
            "is_verified": manufacturer.is_active,
        } if manufacturer else None,
        "summary": {
            "total_batches": len(batch_records),
            "batches_dispatched": dispatched_count_result.scalar_one(),
            "batches_in_transit": in_transit_count_result.scalar_one(),
            "recalled_batches": batch_counts.get(BatchStatus.RECALLED.value, 0),
        },
        "batches": inventory,
        "distributors": distributors,
        "pending_receipts": pending_receipts,
        "recalls": recalls,
        "audit_history": sorted(
            audit_history,
            key=lambda item: item["occurred_at"],
            reverse=True,
        ),
        "documents": documents,
        "notifications": sorted(
            notifications,
            key=lambda item: item["created_at"],
            reverse=True,
        ),
    }


@router.post("/recalls", response_model=RecallResponse)
async def initiate_recall(
    payload: RecallCreate,
    current_user: User = Depends(require_roles(MANUFACTURER_ROLES)),
    db: AsyncSession = Depends(get_db),
):
    return await RecallService.initiate_batch_recall(
        db,
        batch_id=payload.batch_id,
        user=current_user,
        reason=payload.recall_reason,
        severity=payload.severity,
    )


@router.post("/batches/{batch_id}/documents", status_code=201)
async def upload_batch_document(
    batch_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(require_roles(MANUFACTURER_ROLES)),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    batch_result = await db.execute(
        select(Batch)
        .join(Product, Batch.product_id == Product.id)
        .where(
            Batch.id == batch_id,
            Product.manufacturer_id == current_user.organization_id,
        )
    )
    batch = batch_result.scalar_one_or_none()
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")

    original_filename = Path(file.filename or "").name
    extension = Path(original_filename).suffix.lower()
    allowed_type = ALLOWED_DOCUMENT_TYPES.get(extension)
    if not allowed_type or file.content_type != allowed_type[0]:
        raise HTTPException(
            status_code=415,
            detail="Only PDF, PNG, and JPEG documents are accepted.",
        )

    content = bytearray()
    while chunk := await file.read(64 * 1024):
        content.extend(chunk)
        if len(content) > settings.DOCUMENT_MAX_SIZE_BYTES:
            raise HTTPException(status_code=413, detail="Document exceeds the 10 MB limit.")
    await file.close()
    if not content.startswith(allowed_type[1]):
        raise HTTPException(status_code=415, detail="File content does not match its declared type.")

    stored_filename = f"{uuid4().hex}{extension}"
    root = _document_root()
    root.mkdir(parents=True, exist_ok=True)
    storage_path = (root / stored_filename).resolve()
    if storage_path.parent != root:
        raise HTTPException(status_code=400, detail="Invalid document path.")

    try:
        storage_path.write_bytes(content)
        document = BatchDocument(
            batch_id=batch.id,
            organization_id=current_user.organization_id,
            uploaded_by=current_user.id,
            original_filename=original_filename[:255],
            stored_filename=stored_filename,
            content_type=allowed_type[0],
            file_size=len(content),
        )
        db.add(document)
        await db.commit()
        await db.refresh(document)
    except Exception:
        await db.rollback()
        storage_path.unlink(missing_ok=True)
        raise

    return {
        "id": document.id,
        "batch_id": document.batch_id,
        "original_filename": document.original_filename,
        "content_type": document.content_type,
        "file_size": document.file_size,
        "created_at": document.created_at,
    }


@router.get("/documents/{document_id}/download")
async def download_batch_document(
    document_id: str,
    current_user: User = Depends(require_roles(MANUFACTURER_ROLES)),
    db: AsyncSession = Depends(get_db),
) -> FileResponse:
    document = await db.get(BatchDocument, document_id)
    if not document or document.organization_id != current_user.organization_id:
        raise HTTPException(status_code=404, detail="Document not found")

    root = _document_root()
    storage_path = (root / document.stored_filename).resolve()
    if storage_path.parent != root or not storage_path.is_file():
        raise HTTPException(status_code=404, detail="Stored document not found")
    return FileResponse(
        storage_path,
        media_type=document.content_type,
        filename=document.original_filename,
    )
