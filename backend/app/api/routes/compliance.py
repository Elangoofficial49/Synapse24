from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.core.permissions import get_current_user, require_roles
from app.models import (
    SuspiciousActivityAlert, Dispute, CorrectionEvent, Recall, User, UserRole,
    AlertReviewStatus, DisputeStatus
)
from app.schemas import (
    AlertResponse, AlertReviewUpdate, DisputeResponse, DisputeResolveRequest,
    RecallCreate, RecallResponse
)
from app.services.dispute_service import DisputeService
from app.services.recall_service import RecallService

router = APIRouter(tags=["Compliance, Disputes & Governance"])

# Alerts
@router.get("/alerts", response_model=List[AlertResponse])
async def list_alerts(
    status: Optional[AlertReviewStatus] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(SuspiciousActivityAlert)
    if status:
        stmt = stmt.where(SuspiciousActivityAlert.review_status == status)
    result = await db.execute(stmt.order_by(SuspiciousActivityAlert.created_at.desc()))
    return result.scalars().all()

@router.put("/alerts/{alert_id}", response_model=AlertResponse)
async def update_alert(
    alert_id: str,
    payload: AlertReviewUpdate,
    current_user: User = Depends(require_roles([UserRole.ADMIN, UserRole.AUDITOR])),
    db: AsyncSession = Depends(get_db)
):
    alert = await db.get(SuspiciousActivityAlert, alert_id)
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    
    alert.review_status = payload.review_status
    if payload.investigator_notes:
        alert.investigator_notes = payload.investigator_notes
    if payload.resolution_outcome:
        alert.resolution_outcome = payload.resolution_outcome
    alert.assigned_to = current_user.id
    
    await db.commit()
    await db.refresh(alert)
    return alert

# Disputes
@router.get("/disputes", response_model=List[DisputeResponse])
async def list_disputes(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Dispute).order_by(Dispute.created_at.desc()))
    return result.scalars().all()

@router.post("/disputes/{dispute_id}/resolve", response_model=DisputeResponse)
async def resolve_dispute(
    dispute_id: str,
    payload: DisputeResolveRequest,
    current_user: User = Depends(require_roles([UserRole.ADMIN, UserRole.AUDITOR])),
    db: AsyncSession = Depends(get_db)
):
    return await DisputeService.resolve_dispute(
        db,
        dispute_id=dispute_id,
        reviewer=current_user,
        resolution_notes=payload.resolution_notes,
        status=payload.status,
        correction_justification=payload.correction_justification
    )

# Recalls
@router.post("/recalls", response_model=RecallResponse)
async def create_recall(
    payload: RecallCreate,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN, UserRole.AUDITOR])),
    db: AsyncSession = Depends(get_db)
):
    return await RecallService.initiate_batch_recall(
        db,
        batch_id=payload.batch_id,
        user=current_user,
        reason=payload.recall_reason,
        severity=payload.severity
    )

@router.get("/recalls", response_model=List[RecallResponse])
async def list_recalls(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Recall).order_by(Recall.created_at.desc()))
    return result.scalars().all()

