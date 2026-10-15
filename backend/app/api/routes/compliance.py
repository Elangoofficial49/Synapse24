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


@router.post("/alerts/report")
async def report_suspicious_alert(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models import AlertSeverity, AlertType
    package_serial_id = payload.get("package_serial_id", "").strip()
    reason = payload.get("reason", "").strip()
    severity_str = payload.get("severity", "high").strip().lower()
    if not reason:
        raise HTTPException(status_code=400, detail="Reason is required.")

    severity_map = {
        "low": AlertSeverity.LOW,
        "medium": AlertSeverity.MEDIUM,
        "high": AlertSeverity.HIGH,
        "critical": AlertSeverity.CRITICAL,
    }
    severity = severity_map.get(severity_str, AlertSeverity.HIGH)

    package_id = None
    if package_serial_id:
        from app.models import SerializedPackage
        p_res = await db.execute(
            select(SerializedPackage.id).where(
                SerializedPackage.package_serial_id == package_serial_id
            )
        )
        package_id = p_res.scalar_one_or_none()

    alert = SuspiciousActivityAlert(
        alert_type=AlertType.SUSPICIOUS_REPORT if hasattr(AlertType, "SUSPICIOUS_REPORT") else AlertType.UNKNOWN_PACKAGE,
        severity=severity,
        package_id=package_id,
        reason=f"Reported by {current_user.full_name}: {reason}" + (f" (Serial: {package_serial_id})" if package_serial_id else ""),
        evidence_json={"reporter_user_id": current_user.id, "reporter_org_id": current_user.organization_id},
        review_status=AlertReviewStatus.OPEN,
    )
    db.add(alert)
    await db.commit()
    await db.refresh(alert)
    return {
        "status": "success",
        "alert_id": alert.id,
        "severity": alert.severity.value,
        "review_status": alert.review_status.value,
        "created_at": alert.created_at.isoformat(),
    }

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

@router.get("/disputes/{dispute_id}", response_model=DisputeResponse)
async def get_dispute(
    dispute_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    dispute = await db.get(Dispute, dispute_id)
    if not dispute:
        raise HTTPException(status_code=404, detail="Dispute not found")
    return dispute

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


@router.put("/disputes/{dispute_id}/investigate")
async def update_dispute_investigation(
    dispute_id: str,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Feature C: Discrepancy Investigation Workflow.
    Update status, record evidence hash, and append discussion log.
    """
    status_str = payload.get("status", "under_investigation").lower()
    status_map = {
        "open": DisputeStatus.OPEN,
        "under_investigation": DisputeStatus.UNDER_INVESTIGATION,
        "resolved": DisputeStatus.RESOLVED,
        "escalated": DisputeStatus.ESCALATED,
    }
    status = status_map.get(status_str, DisputeStatus.UNDER_INVESTIGATION)
    comments = payload.get("comments") or payload.get("investigation_notes")
    evidence_hash = payload.get("evidence_hash")
    evidence_reference = payload.get("evidence_reference")

    return await DisputeService.update_investigation(
        db,
        dispute_id=dispute_id,
        user=current_user,
        status=status,
        comments=comments,
        evidence_hash=evidence_hash,
        evidence_reference=evidence_reference
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


@router.get("/recalls/{batch_id}/impact")
async def get_recall_impact(
    batch_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Feature B: Recall Impact Simulator.
    Traces affected batch downstream through distributors and pharmacies,
    reporting actual recorded quantities, receipt status, and acknowledgement status.
    """
    return await RecallService.get_recall_impact_simulation(db, batch_id)


@router.post("/recalls/{recall_id}/acknowledge")
async def acknowledge_recall_directive(
    recall_id: str,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Downstream Recall Response:
    Distributor / Pharmacy marks affected stock as quarantined and records confirmation.
    """
    quarantined_qty = int(payload.get("quarantined_quantity", 0))
    notes = payload.get("response_notes")
    return await RecallService.acknowledge_recall(
        db,
        recall_id=recall_id,
        user=current_user,
        quarantined_quantity=quarantined_qty,
        response_notes=notes
    )
