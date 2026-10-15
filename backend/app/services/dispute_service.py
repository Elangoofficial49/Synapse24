from datetime import datetime
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi import HTTPException

from app.models import Dispute, CorrectionEvent, User, DisputeStatus
from app.blockchain.factory import get_blockchain_adapter

class DisputeService:
    @staticmethod
    async def resolve_dispute(
        db: AsyncSession,
        dispute_id: str,
        reviewer: User,
        resolution_notes: str,
        status: DisputeStatus,
        correction_justification: Optional[str] = None
    ) -> Dispute:
        dispute = await db.get(Dispute, dispute_id)
        if not dispute:
            raise HTTPException(status_code=404, detail="Dispute not found")

        dispute.status = status
        dispute.resolution_notes = resolution_notes
        dispute.resolved_by = reviewer.id
        dispute.resolved_at = datetime.utcnow()

        # Append-Only Correction Record (Innovation #4: Never overwrite historical events)
        adapter = get_blockchain_adapter()
        tx = await adapter.resolve_dispute({
            "dispute_id": dispute.id,
            "shipment_id": dispute.shipment_id,
            "resolved_by": reviewer.id,
            "status": status.value
        })

        if correction_justification:
            corr = CorrectionEvent(
                dispute_id=dispute.id,
                shipment_id=dispute.shipment_id,
                correction_type="QUANTITY_ADJUSTMENT",
                corrected_by=reviewer.id,
                original_value=f"Expected: {dispute.expected_quantity}, Received: {dispute.actual_quantity}",
                corrected_value=f"Reconciled via resolution notes",
                justification=correction_justification,
                blockchain_tx_ref=tx.get("tx_id")
            )
            db.add(corr)
            await adapter.record_correction({
                "dispute_id": dispute.id,
                "tx_ref": tx.get("tx_id"),
                "justification": correction_justification
            })

        await db.commit()
        await db.refresh(dispute)
        return dispute

