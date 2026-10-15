from fastapi import APIRouter, Depends
from typing import List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.models import Organization
from app.schemas import OrganizationResponse

router = APIRouter(prefix="/organizations", tags=["Organizations"])

@router.get("", response_model=List[OrganizationResponse])
async def list_organizations(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Organization).order_by(Organization.name))
    return result.scalars().all()

