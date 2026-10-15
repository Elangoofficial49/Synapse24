from datetime import datetime
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from fastapi import HTTPException

from app.models import Recall, Batch, SerializedPackage, User, BatchStatus, PackageStatus, RecallSeverity, RecallStatus
from app.blockchain.factory import get_blockchain_adapter

class RecallService:
    @staticmethod
    async def initiate_batch_recall(
        db: AsyncSession,
        batch_id: str,
        user: User,
        reason: str,
        severity: RecallSeverity
    ) -> Recall:
        batch = await db.get(Batch, batch_id)
        if not batch:
            raise HTTPException(status_code=404, detail="Batch not found")

        # Mark batch as recalled
        batch.status = BatchStatus.RECALLED
        batch.recall_reason = reason

        # Mark all serialized packages in this batch as recalled
        stmt = (
            update(SerializedPackage)
            .where(SerializedPackage.batch_id == batch.id)
            .values(status=PackageStatus.RECALLED)
        )
        await db.execute(stmt)

        # Count affected packages
        pkg_count = (await db.execute(
            select(SerializedPackage).where(SerializedPackage.batch_id == batch.id)
        )).scalars().all()

        recall = Recall(
            batch_id=batch.id,
            initiated_by=user.id,
            recall_reason=reason,
            severity=severity,
            affected_package_count=len(pkg_count),
            status=RecallStatus.ACTIVE
        )
        db.add(recall)

        adapter = get_blockchain_adapter()
        await adapter.recall_batch({
            "batch_id": batch.id,
            "batch_number": batch.batch_number,
            "initiated_by": user.id,
            "reason": reason,
            "affected_count": len(pkg_count)
        })

        await db.commit()
        await db.refresh(recall)
        return recall

