from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.db.session import get_db
from app.core.permissions import get_current_user
from app.models import (
    Product, Batch, SerializedPackage, Shipment, SuspiciousActivityAlert,
    Dispute, Recall, Organization, User, ShipmentStatus
)

router = APIRouter(prefix="/analytics", tags=["Analytics & Reporting"])

@router.get("/dashboard")
async def get_dashboard_metrics(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    total_products = (await db.execute(select(func.count(Product.id)))).scalar_one()
    total_batches = (await db.execute(select(func.count(Batch.id)))).scalar_one()
    total_packages = (await db.execute(select(func.count(SerializedPackage.id)))).scalar_one()
    total_shipments = (await db.execute(select(func.count(Shipment.id)))).scalar_one()
    open_alerts = (await db.execute(select(func.count(SuspiciousActivityAlert.id)).where(SuspiciousActivityAlert.review_status == "open"))).scalar_one()
    open_disputes = (await db.execute(select(func.count(Dispute.id)).where(Dispute.status == "open"))).scalar_one()
    active_recalls = (await db.execute(select(func.count(Recall.id)).where(Recall.status == "active"))).scalar_one()

    # Shipment status counts
    shipment_status_res = await db.execute(
        select(Shipment.status, func.count(Shipment.id)).group_by(Shipment.status)
    )
    status_breakdown = {status.value: count for status, count in shipment_status_res.all()}

    return {
        "summary": {
            "total_products": total_products,
            "total_batches": total_batches,
            "total_packages": total_packages,
            "total_shipments": total_shipments,
            "open_alerts": open_alerts,
            "open_disputes": open_disputes,
            "active_recalls": active_recalls
        },
        "shipment_breakdown": status_breakdown,
        "user_context": {
            "role": current_user.role.value,
            "organization_id": current_user.organization_id
        }
    }

