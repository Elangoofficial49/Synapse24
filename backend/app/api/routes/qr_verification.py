from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.core.permissions import get_optional_user
from app.models import User
from app.schemas import PackageVerificationResponse
from app.services.pharma_service import PharmaService

router = APIRouter(tags=["QR Verification"])

class QRVerifyRequest(BaseModel):
    raw_data: str
    scan_location: Optional[str] = None

@router.post("/verify", response_model=PackageVerificationResponse)
async def verify_package(
    payload: QRVerifyRequest,
    current_user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Public and authenticated endpoint for verifying pharmaceutical package QR code.
    Performs anomaly detection, checks recall/quarantine/expiry statuses,
    and returns verified provenance timeline.
    """
    return await PharmaService.verify_package_scan(db, payload.raw_data, current_user)

