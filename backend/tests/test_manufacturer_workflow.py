from datetime import date

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import settings
from app.core.security import hash_password
from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app.models import (
    Batch,
    Organization,
    OrgType,
    PackageStatus,
    Product,
    SerializedPackage,
    Shipment,
    ShipmentItem,
    ShipmentStatus,
    User,
    UserRole,
)


@pytest.mark.asyncio
async def test_manufacturer_dashboard_and_document_access(tmp_path, monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    monkeypatch.setattr(settings, "DOCUMENT_STORAGE_PATH", str(tmp_path))

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    async with session_factory() as session:
        manufacturer = Organization(
            name="Dashboard Manufacturer",
            org_type=OrgType.MANUFACTURER,
            license_number="TEST-MFR-DASHBOARD",
            address="Manufacturer address",
            contact_email="manufacturer-dashboard@example.com",
        )
        other_manufacturer = Organization(
            name="Other Manufacturer",
            org_type=OrgType.MANUFACTURER,
            license_number="TEST-MFR-OTHER",
            address="Other address",
            contact_email="other-manufacturer@example.com",
        )
        verified_distributor = Organization(
            name="Verified Distributor",
            org_type=OrgType.DISTRIBUTOR,
            license_number="TEST-MFR-DIST-ACTIVE",
            address="Distributor address",
            contact_email="verified-distributor@example.com",
            is_active=True,
        )
        unverified_distributor = Organization(
            name="Unverified Distributor",
            org_type=OrgType.DISTRIBUTOR,
            license_number="TEST-MFR-DIST-PENDING",
            address="Pending distributor address",
            contact_email="unverified-distributor@example.com",
            is_active=False,
        )
        session.add_all(
            [
                manufacturer,
                other_manufacturer,
                verified_distributor,
                unverified_distributor,
            ]
        )
        await session.flush()

        manufacturer_user = User(
            email="manufacturer-dashboard@example.com",
            hashed_password=hash_password("ManufacturerDashboard123!"),
            full_name="Dashboard Manufacturer",
            organization_id=manufacturer.id,
            role=UserRole.MANUFACTURER,
            is_active=True,
        )
        other_user = User(
            email="other-manufacturer-dashboard@example.com",
            hashed_password=hash_password("OtherManufacturer123!"),
            full_name="Other Manufacturer",
            organization_id=other_manufacturer.id,
            role=UserRole.MANUFACTURER,
            is_active=True,
        )
        session.add_all([manufacturer_user, other_user])
        await session.flush()

        product = Product(
            name="Dashboard Medicine",
            generic_name="Dashboard ingredient",
            manufacturer_id=manufacturer.id,
            product_code="TEST-MFR-DASHBOARD-PRODUCT",
            dosage_form="Tablet",
            strength="10 mg",
        )
        other_product = Product(
            name="Other Medicine",
            generic_name="Other ingredient",
            manufacturer_id=other_manufacturer.id,
            product_code="TEST-MFR-OTHER-PRODUCT",
            dosage_form="Tablet",
            strength="20 mg",
        )
        session.add_all([product, other_product])
        await session.flush()

        batch = Batch(
            product_id=product.id,
            batch_number="TEST-MFR-DASHBOARD-BATCH",
            manufacturing_date=date(2026, 1, 1),
            expiry_date=date(2027, 1, 1),
            quantity_manufactured=1,
            created_by=manufacturer_user.id,
        )
        other_batch = Batch(
            product_id=other_product.id,
            batch_number="TEST-MFR-OTHER-BATCH",
            manufacturing_date=date(2026, 1, 1),
            expiry_date=date(2027, 1, 1),
            quantity_manufactured=1,
            created_by=other_user.id,
        )
        session.add_all([batch, other_batch])
        await session.flush()

        package = SerializedPackage(
            package_serial_id="PT-MFR-DASHBOARD-001",
            batch_id=batch.id,
            current_custodian_org_id=verified_distributor.id,
            status=PackageStatus.RECEIVED,
            qr_code_data="PT-MFR-DASHBOARD-001",
        )
        session.add(package)
        await session.flush()

        completed_shipment = Shipment(
            shipment_reference="TEST-MFR-COMPLETED-SHIPMENT",
            sender_org_id=manufacturer.id,
            receiver_org_id=verified_distributor.id,
            status=ShipmentStatus.RECEIVED,
            declared_quantity=1,
            received_quantity=1,
            created_by=manufacturer_user.id,
        )
        session.add(completed_shipment)
        await session.flush()
        session.add(
            ShipmentItem(
                shipment_id=completed_shipment.id,
                package_id=package.id,
                quantity_dispatched=1,
            )
        )
        await session.commit()
        manufacturer_batch_id = batch.id
        other_batch_id = other_batch.id

    async def override_get_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            manufacturer_login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "manufacturer-dashboard@example.com",
                    "password": "ManufacturerDashboard123!",
                },
            )
            other_login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "other-manufacturer-dashboard@example.com",
                    "password": "OtherManufacturer123!",
                },
            )
            assert manufacturer_login.status_code == 200
            assert other_login.status_code == 200
            manufacturer_token = manufacturer_login.json()["access_token"]
            other_token = other_login.json()["access_token"]
            manufacturer_headers = {
                "Authorization": "Bearer " + manufacturer_token,
            }
            other_headers = {
                "Authorization": "Bearer " + other_token,
            }

            dashboard = await client.get(
                "/api/v1/manufacturer/dashboard", headers=manufacturer_headers
            )
            assert dashboard.status_code == 200
            data = dashboard.json()
            assert data["summary"] == {
                "total_batches": 1,
                "batches_dispatched": 1,
                "batches_in_transit": 0,
                "recalled_batches": 0,
            }
            assert [item["id"] for item in data["batches"]] == [
                manufacturer_batch_id
            ]
            assert {item["name"] for item in data["distributors"]} == {
                "Verified Distributor",
                "Unverified Distributor",
            }
            assert next(
                item for item in data["distributors"]
                if item["name"] == "Unverified Distributor"
            )["is_verified"] is False

            pdf_content = b"%PDF-1.7\nmanufacturer quality certificate"
            upload = await client.post(
                f"/api/v1/manufacturer/batches/{manufacturer_batch_id}/documents",
                headers=manufacturer_headers,
                files={
                    "file": (
                        "quality-certificate.pdf",
                        pdf_content,
                        "application/pdf",
                    )
                },
            )
            assert upload.status_code == 201, upload.text
            document = upload.json()

            download = await client.get(
                f"/api/v1/manufacturer/documents/{document['id']}/download",
                headers=manufacturer_headers,
            )
            assert download.status_code == 200
            assert download.content == pdf_content

            unauthorized_download = await client.get(
                f"/api/v1/manufacturer/documents/{document['id']}/download",
                headers=other_headers,
            )
            assert unauthorized_download.status_code == 404

            unauthorized_upload = await client.post(
                f"/api/v1/manufacturer/batches/{other_batch_id}/documents",
                headers=manufacturer_headers,
                files={"file": ("other.pdf", pdf_content, "application/pdf")},
            )
            assert unauthorized_upload.status_code == 404
    finally:
        app.dependency_overrides.pop(get_db, None)
        await engine.dispose()
