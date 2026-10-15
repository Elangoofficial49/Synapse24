import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.security import hash_password
from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app.models import OrgType, Organization, User, UserRole


@pytest.mark.asyncio
async def test_registration_requires_admin_approval():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    async with session_factory() as session:
        organization = Organization(
            name="PharmaTrace Test Regulator",
            org_type=OrgType.REGULATOR,
            license_number="TEST-ADMIN-LICENSE",
            address="Test address",
            contact_email="admin-org@example.com",
        )
        session.add(organization)
        await session.flush()
        session.add(
            User(
                email="approval-admin@example.com",
                hashed_password=hash_password("AdminTestPassword123!"),
                full_name="Approval Admin",
                organization_id=organization.id,
                role=UserRole.ADMIN,
            )
        )
        await session.commit()

    async def override_get_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            registration = await client.post(
                "/api/v1/auth/register",
                json={
                    "email": "new-manufacturer@example.com",
                    "password": "ManufacturerTest123!",
                    "full_name": "New Manufacturer",
                    "organization_name": "New Pharma Manufacturer",
                    "organization_type": "manufacturer",
                    "license_number": "TEST-MFR-LICENSE",
                    "address": "Factory address",
                    "contact_email": "contact@example.com",
                },
            )
            assert registration.status_code == 202
            assert registration.json()["status"] == "pending_approval"

            denied_login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "new-manufacturer@example.com",
                    "password": "ManufacturerTest123!",
                },
            )
            assert denied_login.status_code == 403

            admin_login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "approval-admin@example.com",
                    "password": "AdminTestPassword123!",
                },
            )
            assert admin_login.status_code == 200
            admin_token = admin_login.json()["access_token"]
            admin_headers = {"Authorization": f"Bearer {admin_token}"}

            pending = await client.get(
                "/api/v1/auth/pending-users", headers=admin_headers
            )
            assert pending.status_code == 200
            new_user = next(
                user for user in pending.json()
                if user["email"] == "new-manufacturer@example.com"
            )
            assert new_user["role"] == "manufacturer"

            approved = await client.post(
                f"/api/v1/auth/users/{new_user['id']}/approve",
                headers=admin_headers,
            )
            assert approved.status_code == 200
            assert approved.json()["is_active"] is True

            successful_login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "new-manufacturer@example.com",
                    "password": "ManufacturerTest123!",
                },
            )
            assert successful_login.status_code == 200
            manufacturer_token = successful_login.json()["access_token"]
            assert successful_login.json()["user"]["role"] == "manufacturer"
            manufacturer_headers = {"Authorization": f"Bearer {manufacturer_token}"}

            product = await client.post(
                "/api/v1/products",
                headers=manufacturer_headers,
                json={
                    "name": "Test medicine",
                    "generic_name": "Test ingredient",
                    "product_code": "TEST-PRD-01",
                    "dosage_form": "Tablet",
                    "strength": "10 mg",
                },
            )
            assert product.status_code == 200

            batch = await client.post(
                "/api/v1/batches",
                headers=manufacturer_headers,
                json={
                    "product_id": product.json()["id"],
                    "batch_number": "TEST-BATCH-01",
                    "manufacturing_date": "2026-01-01",
                    "expiry_date": "2027-01-01",
                    "quantity_manufactured": 2,
                },
            )
            assert batch.status_code == 200

            generated = await client.post(
                f"/api/v1/batches/{batch.json()['id']}/generate-packages",
                headers=manufacturer_headers,
                json={"batch_id": batch.json()["id"], "count": 1},
            )
            assert generated.status_code == 200
            package_qr = generated.json()[0]["qr_code_data"]

            verification = await client.post(
                "/api/v1/verify",
                headers=manufacturer_headers,
                json={"raw_data": package_qr},
            )
            assert verification.status_code == 200
            package_details = verification.json()
            assert package_details["is_valid"] is True
            assert package_details["manufacturer_name"] == "New Pharma Manufacturer"
            assert package_details["generic_name"] == "Test ingredient"
            assert package_details["manufacturing_date"] == "2026-01-01"
            assert package_details["recent_events"][0]["to_organization"] == "New Pharma Manufacturer"

            admin_qr_generation = await client.post(
                f"/api/v1/batches/{batch.json()['id']}/generate-packages",
                headers=admin_headers,
                json={"batch_id": batch.json()["id"], "count": 1},
            )
            assert admin_qr_generation.status_code == 403
    finally:
        app.dependency_overrides.pop(get_db, None)
        await engine.dispose()
