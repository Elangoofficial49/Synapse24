from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.core.permissions import get_current_user
from app.models import Shipment, User
from app.schemas import (
    ShipmentCreate, ShipmentResponse, ShipmentReceiveRequest,
    ShipmentSplitRequest
)
from app.services.custody_service import CustodyService

router = APIRouter(prefix="/shipments", tags=["Shipments & Custody Transfers"])

@router.post("", response_model=ShipmentResponse)
async def create_shipment(
    payload: ShipmentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    return await CustodyService.create_and_dispatch_shipment(
        db,
        sender=current_user,
        receiver_org_id=payload.receiver_org_id,
        package_serial_ids=payload.package_serial_ids,
        transporter_org_id=payload.transporter_org_id,
        notes=payload.notes
    )

@router.get("", response_model=List[ShipmentResponse])
async def list_shipments(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Shipment).where(
        (Shipment.sender_org_id == current_user.organization_id) |
        (Shipment.receiver_org_id == current_user.organization_id)
    ).order_by(Shipment.created_at.desc())
    result = await db.execute(stmt)
    return result.scalars().all()

@router.get("/{shipment_id}", response_model=ShipmentResponse)
async def get_shipment(
    shipment_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    shipment = await db.get(Shipment, shipment_id)
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return shipment

@router.post("/{shipment_id}/receive")
async def receive_shipment(
    shipment_id: str,
    payload: ShipmentReceiveRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Two-Party Custody Verification:
    Recipient independently confirms actual quantity received.
    Triggers dispute and flags anomalies if quantities mismatch.
    """
    result = await CustodyService.process_shipment_receipt(
        db,
        shipment_id=shipment_id,
        receiver=current_user,
        actual_quantity_received=payload.actual_quantity_received,
        scanned_serial_ids=payload.scanned_package_serial_ids,
        notes=payload.notes
    )
    return {
        "status": "success",
        "shipment_id": result["shipment"].id,
        "shipment_status": result["shipment"].status.value,
        "declared_quantity": result["shipment"].declared_quantity,
        "received_quantity": result["shipment"].received_quantity,
        "discrepancy_detected": result["discrepancy"],
        "dispute_id": result["dispute_id"],
        "tx_reference": result["tx_reference"]
    }

@router.post("/{shipment_id}/split", response_model=List[ShipmentResponse])
async def split_shipment(
    shipment_id: str,
    payload: ShipmentSplitRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Split inventory into child shipments and reconcile quantities.
    Ensures sum(children) <= received quantity.
    """
    return await CustodyService.split_shipment(
        db,
        parent_shipment_id=shipment_id,
        user=current_user,
        child_allocations=payload.child_shipments
    )

