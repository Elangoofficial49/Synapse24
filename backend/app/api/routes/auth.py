from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.core.security import verify_password, create_access_token, hash_password
from app.core.permissions import get_current_user, require_roles
from app.models import OrgType, User, UserRole, Organization
from app.schemas import (
    LoginRequest, PendingUserResponse, RegistrationRequest,
    RegistrationResponse, TokenResponse, UserResponse
)

router = APIRouter(prefix="/auth", tags=["Authentication"])

ROLE_BY_ORG_TYPE = {
    OrgType.MANUFACTURER: UserRole.MANUFACTURER,
    OrgType.DISTRIBUTOR: UserRole.DISTRIBUTOR,
    OrgType.TRANSPORTER: UserRole.TRANSPORTER,
    OrgType.PHARMACY: UserRole.PHARMACY_STAFF,
    OrgType.HOSPITAL: UserRole.PHARMACY_STAFF,
    OrgType.REGULATOR: UserRole.AUDITOR,
}

@router.post("/register", response_model=RegistrationResponse, status_code=202)
async def register(
    registration: RegistrationRequest,
    db: AsyncSession = Depends(get_db)
):
    existing_user = await db.execute(select(User.id).where(User.email == registration.email))
    if existing_user.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    existing_license = await db.execute(
        select(Organization.id).where(Organization.license_number == registration.license_number)
    )
    if existing_license.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="An organization with this license number already exists")

    organization = Organization(
        name=registration.organization_name,
        org_type=registration.organization_type,
        license_number=registration.license_number,
        address=registration.address,
        contact_email=registration.contact_email,
        is_active=False,
    )
    db.add(organization)
    await db.flush()

    user = User(
        email=registration.email,
        hashed_password=hash_password(registration.password),
        full_name=registration.full_name,
        organization_id=organization.id,
        role=ROLE_BY_ORG_TYPE[registration.organization_type],
        is_active=False,
    )
    db.add(user)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="An account or organization with these details already exists",
        ) from exc

    return {
        "status": "pending_approval",
        "message": "Registration received. An administrator must approve your organization before you can sign in.",
    }

@router.post("/login", response_model=TokenResponse)
async def login(credentials: LoginRequest, db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(User.email == credentials.email)
    user = (await db.execute(stmt)).scalar_one_or_none()
    
    if not user or not verify_password(credentials.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is disabled")

    org = await db.get(Organization, user.organization_id)
    token = create_access_token(data={"sub": user.id, "role": user.role.value, "org": user.organization_id})
    
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "role": user.role.value,
            "organization_id": user.organization_id,
            "organization_name": org.name if org else ""
        }
    }

@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user

@router.get("/pending-users", response_model=list[PendingUserResponse])
async def list_pending_users(
    current_user: User = Depends(require_roles([UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User, Organization)
        .join(Organization, User.organization_id == Organization.id)
        .where(User.is_active.is_(False))
        .order_by(User.created_at)
    )
    return [
        {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "role": user.role,
            "organization_id": organization.id,
            "organization_name": organization.name,
            "organization_type": organization.org_type,
            "license_number": organization.license_number,
            "contact_email": organization.contact_email,
            "created_at": user.created_at,
        }
        for user, organization in result.all()
    ]

@router.post("/users/{user_id}/approve", response_model=UserResponse)
async def approve_user(
    user_id: str,
    current_user: User = Depends(require_roles([UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db),
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.is_active:
        raise HTTPException(status_code=409, detail="User account is already active")

    user.is_active = True
    organization = await db.get(Organization, user.organization_id)
    if organization:
        organization.is_active = True
    await db.commit()
    await db.refresh(user)
    return user
