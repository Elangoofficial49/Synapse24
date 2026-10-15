import hashlib
import hmac
import secrets
from datetime import datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_

from app.db.session import get_db
from app.core.config import settings
from app.core.permissions import get_current_user
from app.models import Organization, OrgType, Shipment, User, UserRole, RegistrationEmailVerification
from app.schemas import OrganizationPartnerResponse, OrganizationResponse
from app.services.email_service import send_registration_otp_email

router = APIRouter(prefix="/organizations", tags=["Organizations"])

OTP_LIFETIME = timedelta(minutes=10)
OTP_MAX_ATTEMPTS = 5

def _otp_hash(email: str, code: str) -> str:
    return hmac.new(
        settings.SECRET_KEY.encode(),
        f"{email}:{code}".encode(),
        hashlib.sha256,
    ).hexdigest()


@router.post("/distributors/send-otp")
async def send_distributor_onboarding_otp(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != UserRole.MANUFACTURER:
        raise HTTPException(
            status_code=403,
            detail="Only manufacturers are authorized to onboard and verify distributors.",
        )

    email = (payload.get("contact_email") or "").strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="A valid contact email is required.")

    code = f"{secrets.randbelow(1_000_000):06d}"
    email_sent = False

    if settings.BREVO_API_KEY and settings.BREVO_SENDER_EMAIL:
        try:
            await send_registration_otp_email(email, code)
            email_sent = True
        except Exception:
            pass

    now = datetime.utcnow()
    verification = await db.get(RegistrationEmailVerification, email)
    if verification is None:
        verification = RegistrationEmailVerification(email=email)
        db.add(verification)

    verification.code_hash = _otp_hash(email, code)
    verification.expires_at = now + OTP_LIFETIME
    verification.sent_at = now
    verification.attempts = 0
    verification.verified_until = None
    await db.commit()

    return {
        "message": f"Verification OTP sent to {email}.",
        "email_delivered": email_sent,
        "demo_code": code if not email_sent else None,
    }


@router.post("/distributors/onboard", response_model=OrganizationResponse)
async def onboard_verified_distributor(
    distributor_data: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != UserRole.MANUFACTURER:
        raise HTTPException(
            status_code=403,
            detail="Only manufacturers are authorized to onboard and verify distributors.",
        )

    name = (distributor_data.get("name") or "").strip()
    license_number = (distributor_data.get("license_number") or "").strip().upper()
    address = (distributor_data.get("address") or "").strip()
    contact_email = (distributor_data.get("contact_email") or "").strip().lower()
    otp_code = (distributor_data.get("otp_code") or "").strip()

    if not name or not license_number or not address or not contact_email:
        raise HTTPException(
            status_code=400,
            detail="Distributor name, valid regulatory license number, warehouse address, and contact email are required.",
        )

    if otp_code:
        verification = await db.get(RegistrationEmailVerification, contact_email)
        now = datetime.utcnow()
        if not verification or verification.expires_at <= now:
            raise HTTPException(
                status_code=400,
                detail="The OTP verification code has expired. Request a new code.",
            )
        if verification.attempts >= OTP_MAX_ATTEMPTS:
            raise HTTPException(
                status_code=429,
                detail="Too many incorrect OTP attempts. Request a new verification code.",
            )
        if not hmac.compare_digest(
            verification.code_hash,
            _otp_hash(contact_email, otp_code),
        ):
            verification.attempts += 1
            await db.commit()
            raise HTTPException(
                status_code=400,
                detail="The OTP verification code is incorrect.",
            )
        verification.code_hash = ""
        verification.verified_until = now + timedelta(minutes=60)
        await db.commit()

    # 1. Check if user or org already exists
    existing_user_result = await db.execute(
        select(User).where(User.email == contact_email)
    )
    existing_user = existing_user_result.scalar_one_or_none()

    existing_org_result = await db.execute(
        select(Organization).where(
            or_(
                Organization.license_number == license_number,
                Organization.contact_email == contact_email,
            )
        )
    )
    existing_org = existing_org_result.scalar_one_or_none()

    if existing_org:
        distributor = existing_org
        distributor.name = name
        distributor.address = address
        distributor.license_number = license_number
        distributor.contact_email = contact_email
        distributor.is_active = True
        distributor.org_type = OrgType.DISTRIBUTOR

        if existing_user:
            existing_user.organization_id = distributor.id
            existing_user.is_active = True
            existing_user.role = UserRole.DISTRIBUTOR

        await db.commit()
        await db.refresh(distributor)
        return distributor

    if existing_user:
        distributor = Organization(
            name=name,
            org_type=OrgType.DISTRIBUTOR,
            license_number=license_number,
            address=address,
            contact_email=contact_email,
            is_active=True,
        )
        db.add(distributor)
        await db.flush()

        existing_user.organization_id = distributor.id
        existing_user.is_active = True
        existing_user.role = UserRole.DISTRIBUTOR
        await db.commit()
        await db.refresh(distributor)
        return distributor

    distributor = Organization(
        name=name,
        org_type=OrgType.DISTRIBUTOR,
        license_number=license_number,
        address=address,
        contact_email=contact_email,
        is_active=True,
    )
    db.add(distributor)
    await db.commit()
    await db.refresh(distributor)
    return distributor


@router.post("/pharmacies/send-otp")
async def send_pharmacy_onboarding_otp(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != UserRole.DISTRIBUTOR:
        raise HTTPException(
            status_code=403,
            detail="Only distributors are authorized to onboard and verify pharmacies.",
        )

    email = (payload.get("contact_email") or "").strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="A valid contact email is required.")

    code = f"{secrets.randbelow(1_000_000):06d}"
    email_sent = False

    if settings.BREVO_API_KEY and settings.BREVO_SENDER_EMAIL:
        try:
            await send_registration_otp_email(email, code)
            email_sent = True
        except Exception:
            pass

    now = datetime.utcnow()
    verification = await db.get(RegistrationEmailVerification, email)
    if verification is None:
        verification = RegistrationEmailVerification(email=email)
        db.add(verification)

    verification.code_hash = _otp_hash(email, code)
    verification.expires_at = now + OTP_LIFETIME
    verification.sent_at = now
    verification.attempts = 0
    verification.verified_until = None
    await db.commit()

    return {
        "message": f"Verification OTP sent to {email}.",
        "email_delivered": email_sent,
        # For testing / demo fallback when email services are throttled or in offline test mode
        "demo_code": code if not email_sent else None,
    }


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
        .order_by(Organization.created_at.desc())
    )
    return result.scalars().all()


@router.post("/pharmacies/onboard", response_model=OrganizationResponse)
async def onboard_verified_pharmacy(
    pharmacy_data: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role != UserRole.DISTRIBUTOR:
        raise HTTPException(
            status_code=403,
            detail="Only distributors are authorized to onboard and verify pharmacies.",
        )

    name = (pharmacy_data.get("name") or "").strip()
    license_number = (pharmacy_data.get("license_number") or "").strip().upper()
    address = (pharmacy_data.get("address") or "").strip()
    contact_email = (pharmacy_data.get("contact_email") or "").strip().lower()
    otp_code = (pharmacy_data.get("otp_code") or "").strip()

    if not name or not license_number or not address or not contact_email:
        raise HTTPException(
            status_code=400,
            detail="Pharmacy name, valid regulatory license number, delivery address, and contact email are required.",
        )

    # Validate OTP if provided
    if otp_code:
        verification = await db.get(RegistrationEmailVerification, contact_email)
        now = datetime.utcnow()
        if not verification or verification.expires_at <= now:
            raise HTTPException(
                status_code=400,
                detail="The OTP verification code has expired. Request a new code.",
            )
        if verification.attempts >= OTP_MAX_ATTEMPTS:
            raise HTTPException(
                status_code=429,
                detail="Too many incorrect OTP attempts. Request a new verification code.",
            )
        if not hmac.compare_digest(
            verification.code_hash,
            _otp_hash(contact_email, otp_code),
        ):
            verification.attempts += 1
            await db.commit()
            raise HTTPException(
                status_code=400,
                detail="The OTP verification code is incorrect.",
            )
        # Mark as verified
        verification.code_hash = ""
        verification.verified_until = now + timedelta(minutes=60)
        await db.commit()

    # 1. Check if an account or organization already registered with this email or license number
    existing_user_result = await db.execute(
        select(User).where(User.email == contact_email)
    )
    existing_user = existing_user_result.scalar_one_or_none()

    existing_org_result = await db.execute(
        select(Organization).where(
            or_(
                Organization.license_number == license_number,
                Organization.contact_email == contact_email,
            )
        )
    )
    existing_org = existing_org_result.scalar_one_or_none()

    if existing_org:
        # If the pharmacy profile already exists, update and verify it
        pharmacy = existing_org
        pharmacy.name = name
        pharmacy.address = address
        pharmacy.license_number = license_number
        pharmacy.contact_email = contact_email
        pharmacy.is_active = True

        # Activate the registered user so they can login and see dispatched orders
        if existing_user:
            existing_user.organization_id = pharmacy.id
            existing_user.is_active = True
            existing_user.role = UserRole.PHARMACY_STAFF

        await db.commit()
        await db.refresh(pharmacy)
        return pharmacy

    # 2. If user exists with this email but without active org
    if existing_user:
        pharmacy = Organization(
            name=name,
            org_type=OrgType.PHARMACY,
            license_number=license_number,
            address=address,
            contact_email=contact_email,
            is_active=True,
        )
        db.add(pharmacy)
        await db.flush()

        existing_user.organization_id = pharmacy.id
        existing_user.is_active = True
        existing_user.role = UserRole.PHARMACY_STAFF
        await db.commit()
        await db.refresh(pharmacy)
        return pharmacy

    # 3. New pharmacy organization registration
    pharmacy = Organization(
        name=name,
        org_type=OrgType.PHARMACY,
        license_number=license_number,
        address=address,
        contact_email=contact_email,
        is_active=True,
    )
    db.add(pharmacy)
    await db.commit()
    await db.refresh(pharmacy)
    return pharmacy
