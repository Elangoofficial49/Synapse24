from fastapi import APIRouter, Depends, HTTPException
from typing import List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.core.permissions import get_current_user
from app.models import Organization, OrgType, Shipment, User, UserRole
from app.schemas import OrganizationPartnerResponse, OrganizationResponse

router = APIRouter(prefix="/organizations", tags=["Organizations"])

@router.get("", response_model=List[OrganizationResponse])
async def list_organizations(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Organization).order_by(Organization.name))
    return result.scalars().all()


@router.get("/partners", response_model=List[OrganizationPartnerResponse])
async def list_distributor_partners(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != UserRole.DISTRIBUTOR:
        raise HTTPException(
            status_code=403,
            detail="Only distributors can view wholesaler partners.",
        )

    partner_ids = select(Shipment.receiver_org_id.label("partner_id")).where(
        Shipment.sender_org_id == current_user.organization_id
    ).union(
        select(Shipment.sender_org_id.label("partner_id")).where(
            Shipment.receiver_org_id == current_user.organization_id
        )
    ).subquery()
    result = await db.execute(
        select(Organization)
        .join(partner_ids, Organization.id == partner_ids.c.partner_id)
        .where(
            Organization.org_type == OrgType.DISTRIBUTOR,
            Organization.is_active.is_(True),
            Organization.id != current_user.organization_id,
        )
        .order_by(Organization.name)
    )
    return result.scalars().all()


@router.get("/pharmacies", response_model=List[OrganizationResponse])
async def list_verified_pharmacies(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != UserRole.DISTRIBUTOR:
        raise HTTPException(
            status_code=403,
            detail="Only distributors can view the pharmacy directory.",
        )

    result = await db.execute(
        select(Organization)
        .where(
            Organization.org_type == OrgType.PHARMACY,
            Organization.is_active.is_(True),
        )
        .order_by(Organization.name)
    )
    return result.scalars().all()
