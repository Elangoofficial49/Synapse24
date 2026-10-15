import asyncio
from datetime import datetime, date, timedelta
from sqlalchemy import select

from app.db.session import AsyncSessionLocal, async_engine
from app.db.base import Base
from app.core.security import hash_password
from app.models import (
    Organization, User, Product, Batch, SerializedPackage, CustodyEvent,
    OrgType, UserRole, BatchStatus, PackageStatus, CustodyEventType
)
from app.blockchain.factory import get_blockchain_adapter

async def seed_data():
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as db:
        # Check if already seeded
        existing_org = (await db.execute(select(Organization))).first()
        if existing_org:
            print("Database already seeded with demo data.")
            return

        print("Seeding Organizations...")
        mfr_org = Organization(
            name="Apex Bioscience Laboratories",
            org_type=OrgType.MANUFACTURER,
            license_number="LIC-MFR-2024-001",
            address="Plot 42, Biotech Park, Industrial Corridor",
            contact_email="compliance@apexbio.com"
        )
        dist_org = Organization(
            name="FastDist Global Pharma Logistics",
            org_type=OrgType.DISTRIBUTOR,
            license_number="LIC-DST-2024-089",
            address="Central Distribution Center, Gateway Logistics Zone",
            contact_email="ops@fastdist.com"
        )
        rx_org = Organization(
            name="St. Jude Memorial Hospital & Pharmacy",
            org_type=OrgType.HOSPITAL,
            license_number="LIC-HSP-2024-912",
            address="800 Healthcare Boulevard, Metro Health District",
            contact_email="pharmacy@stjude-health.org"
        )
        reg_org = Organization(
            name="National Pharmaceutical Regulatory Authority",
            org_type=OrgType.REGULATOR,
            license_number="GOV-REG-0001",
            address="Federal Regulatory Complex",
            contact_email="audit@npra.gov"
        )
        db.add_all([mfr_org, dist_org, rx_org, reg_org])
        await db.commit()
        await db.refresh(mfr_org)
        await db.refresh(dist_org)
        await db.refresh(rx_org)
        await db.refresh(reg_org)

        print("Seeding Demo Users...")
        # Demo credentials matching plan
        users = [
            User(
                email="admin@pharmatrace.dev",
                hashed_password=hash_password("DevAdmin2024!"),
                full_name="System Administrator",
                organization_id=reg_org.id,
                role=UserRole.ADMIN
            ),
            User(
                email="manufacturer@pharmatrace.dev",
                hashed_password=hash_password("DevMfr2024!"),
                full_name="Dr. Elena Vance (Head of Manufacturing)",
                organization_id=mfr_org.id,
                role=UserRole.MANUFACTURER
            ),
            User(
                email="distributor@pharmatrace.dev",
                hashed_password=hash_password("DevDist2024!"),
                full_name="Marcus Reed (Logistics Director)",
                organization_id=dist_org.id,
                role=UserRole.DISTRIBUTOR
            ),
            User(
                email="pharmacy@pharmatrace.dev",
                hashed_password=hash_password("DevRx2024!"),
                full_name="Dr. Sarah Jenkins (Chief Pharmacist)",
                organization_id=rx_org.id,
                role=UserRole.PHARMACY_STAFF
            ),
            User(
                email="auditor@pharmatrace.dev",
                hashed_password=hash_password("DevAudit2024!"),
                full_name="Agent Arthur Pendelton (Lead Auditor)",
                organization_id=reg_org.id,
                role=UserRole.AUDITOR
            )
        ]
        db.add_all(users)
        await db.commit()
        for u in users:
            await db.refresh(u)

        mfr_user = users[1]

        print("Seeding Pharmaceutical Products & Batches...")
        prod = Product(
            name="Amoxicillin Trihydrate Capsules",
            generic_name="Amoxicillin",
            manufacturer_id=mfr_org.id,
            product_code="NDC-50090-0012",
            dosage_form="Oral Capsule",
            strength="500 mg",
            description="Broad-spectrum beta-lactam antibiotic used in bacterial infections."
        )
        db.add(prod)
        await db.commit()
        await db.refresh(prod)

        batch = Batch(
            product_id=prod.id,
            batch_number="BATCH-2024-AMX01",
            manufacturing_date=date.today() - timedelta(days=30),
            expiry_date=date.today() + timedelta(days=700),
            quantity_manufactured=100,
            created_by=mfr_user.id
        )
        db.add(batch)
        await db.commit()
        await db.refresh(batch)

        print("Seeding Serialized Packages with Verifiable QR IDs...")
        adapter = get_blockchain_adapter()
        packages = []
        for i in range(1, 101):
            serial_id = f"PT-{batch.batch_number}-{i:04d}"
            pkg = SerializedPackage(
                package_serial_id=serial_id,
                batch_id=batch.id,
                current_custodian_org_id=mfr_org.id,
                status=PackageStatus.MANUFACTURED,
                qr_code_data=f"https://verify.pharmatrace.org/v1/pkg/{serial_id}"
            )
            db.add(pkg)
            packages.append(pkg)
        await db.commit()

        # Seed custody event for first few packages
        for pkg in packages[:10]:
            await db.refresh(pkg)
            tx = await adapter.register_package({
                "package_serial_id": pkg.package_serial_id,
                "batch_id": batch.id,
                "custodian_org_id": mfr_org.id
            })
            ev = CustodyEvent(
                package_id=pkg.id,
                event_type=CustodyEventType.MANUFACTURED,
                to_org_id=mfr_org.id,
                performed_by=mfr_user.id,
                notes="Manufactured and packaged at Apex Bioscience",
                blockchain_tx_ref=tx.get("tx_id"),
                is_on_chain=False
            )
            db.add(ev)
        await db.commit()

        print("[OK] Demo dataset successfully created!")
        print("Demo Accounts:")
        print("  - Admin: admin@pharmatrace.dev / DevAdmin2024!")
        print("  - Manufacturer: manufacturer@pharmatrace.dev / DevMfr2024!")
        print("  - Distributor: distributor@pharmatrace.dev / DevDist2024!")
        print("  - Pharmacy: pharmacy@pharmatrace.dev / DevRx2024!")
        print("  - Auditor: auditor@pharmatrace.dev / DevAudit2024!")

if __name__ == "__main__":
    asyncio.run(seed_data())
