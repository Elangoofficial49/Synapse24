from fastapi import APIRouter, Depends, HTTPException, Response
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.core.permissions import get_current_user, require_roles
from app.models import Product, Batch, SerializedPackage, User, UserRole
from app.schemas import (
    ProductCreate, ProductResponse, BatchCreate, BatchResponse,
    PackageGenerateRequest, SerializedPackageResponse
)
from app.services.pharma_service import PharmaService

router = APIRouter(tags=["Products & Batches"])

@router.post("/products", response_model=ProductResponse)
async def create_product(
    product_in: ProductCreate,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db)
):
    return await PharmaService.create_product(db, product_in, current_user.organization_id)

@router.get("/products", response_model=List[ProductResponse])
async def list_products(
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Product)
    if current_user.role != UserRole.ADMIN:
        stmt = stmt.where(Product.manufacturer_id == current_user.organization_id)
    result = await db.execute(stmt.order_by(Product.created_at.desc()))
    return result.scalars().all()

@router.post("/batches", response_model=BatchResponse)
async def create_batch(
    batch_in: BatchCreate,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db)
):
    return await PharmaService.create_batch(db, batch_in, current_user.id)

@router.get("/batches", response_model=List[BatchResponse])
async def list_batches(
    product_id: Optional[str] = None,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Batch).join(Product, Batch.product_id == Product.id)
    if product_id:
        stmt = stmt.where(Batch.product_id == product_id)
    if current_user.role != UserRole.ADMIN:
        stmt = stmt.where(Product.manufacturer_id == current_user.organization_id)
    result = await db.execute(stmt.order_by(Batch.created_at.desc()))
    return result.scalars().all()

@router.post("/batches/{batch_id}/generate-packages", response_model=List[SerializedPackageResponse])
async def generate_packages(
    batch_id: str,
    req: PackageGenerateRequest,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db)
):
    return await PharmaService.generate_packages(db, batch_id, req.count, current_user)

@router.get("/packages", response_model=List[SerializedPackageResponse])
async def list_packages(
    batch_id: Optional[str] = None,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db),
):
    stmt = (
        select(SerializedPackage)
        .join(Batch, SerializedPackage.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
    )
    if batch_id:
        stmt = stmt.where(SerializedPackage.batch_id == batch_id)
    if current_user.role != UserRole.ADMIN:
        stmt = stmt.where(Product.manufacturer_id == current_user.organization_id)
    result = await db.execute(stmt.order_by(SerializedPackage.created_at.desc()).limit(1000))
    return result.scalars().all()

@router.get("/packages/{serial_id}/qr-code")
async def get_package_qr_image(
    serial_id: str,
    current_user: User = Depends(require_roles([UserRole.MANUFACTURER, UserRole.ADMIN])),
    db: AsyncSession = Depends(get_db),
):
    stmt = (
        select(SerializedPackage, Product)
        .join(Batch, SerializedPackage.batch_id == Batch.id)
        .join(Product, Batch.product_id == Product.id)
        .where(SerializedPackage.package_serial_id == serial_id)
    )
    record = (await db.execute(stmt)).first()
    if not record:
        raise HTTPException(status_code=404, detail="Package not found")
    pkg, product = record
    if current_user.role != UserRole.ADMIN and product.manufacturer_id != current_user.organization_id:
        raise HTTPException(status_code=403, detail="You can only access QR codes for your organization's products")
        
    png_bytes = PharmaService.generate_qr_png_bytes(pkg.qr_code_data)
    return Response(content=png_bytes, media_type="image/png")
