from datetime import date

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.security import hash_password
from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app.models import (
    Batch,
    OrgType,
    Organization,
    PackageStatus,
    Product,
    Shipment,
    ShipmentItem,
    ShipmentStatus,
    SerializedPackage,
    User,
    UserRole,
)


@pytest.mark.asyncio
async def test_distributor_partner_inventory_and_transfer_flow():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    async with session_factory() as session:
        manufacturer = Organization(
            name="Test Manufacturer",
            org_type=OrgType.MANUFACTURER,
            license_number="TEST-DIST-MFR",
            address="Manufacturer address",
            contact_email="manufacturer@example.com",
        )
        distributor_org = Organization(
            name="Test Distributor",
            org_type=OrgType.DISTRIBUTOR,
            license_number="TEST-DIST-ORG",
            address="Distributor address",
            contact_email="distributor@example.com",
        )
        wholesaler = Organization(
            name="Existing Wholesaler",
            org_type=OrgType.DISTRIBUTOR,
            license_number="TEST-DIST-WHOLESALER",
            address="Wholesaler address",
            contact_email="wholesaler@example.com",
        )
        pharmacy = Organization(
            name="Verified Pharmacy",
            org_type=OrgType.PHARMACY,
            license_number="TEST-DIST-PHARMACY",
            address="Pharmacy delivery address",
            contact_email="pharmacy@example.com",
            is_active=True,
        )
        unverified_pharmacy = Organization(
            name="Unverified Pharmacy",
            org_type=OrgType.PHARMACY,
            license_number="TEST-DIST-PHARMACY-PENDING",
            address="Pending delivery address",
            contact_email="pending-pharmacy@example.com",
            is_active=False,
        )
        session.add_all([
            manufacturer, distributor_org, wholesaler, pharmacy,
            unverified_pharmacy,
        ])
        await session.flush()

        distributor_user = User(
            email="test-distributor@example.com",
            hashed_password=hash_password("DistributorTest123!"),
            full_name="Test Distributor",
            organization_id=distributor_org.id,
            role=UserRole.DISTRIBUTOR,
            is_active=True,
        )
        manufacturer_user = User(
            email="test-manufacturer@example.com",
            hashed_password=hash_password("ManufacturerTest123!"),
            full_name="Test Manufacturer",
            organization_id=manufacturer.id,
            role=UserRole.MANUFACTURER,
            is_active=True,
        )
        pharmacy_user = User(
            email="test-pharmacy@example.com",
            hashed_password=hash_password("PharmacyTest123!"),
            full_name="Test Pharmacy",
            organization_id=pharmacy.id,
            role=UserRole.PHARMACY_STAFF,
            is_active=True,
        )
        session.add_all([distributor_user, manufacturer_user, pharmacy_user])
        await session.flush()

        product = Product(
            name="Test Medicine",
            generic_name="Test ingredient",
            manufacturer_id=manufacturer.id,
            product_code="TEST-DIST-PRODUCT",
            dosage_form="Tablet",
            strength="10 mg",
        )
        session.add(product)
        await session.flush()
        batch = Batch(
            product_id=product.id,
            batch_number="TEST-DIST-BATCH",
            manufacturing_date=date(2026, 1, 1),
            expiry_date=date(2027, 1, 1),
            quantity_manufactured=3,
            created_by=manufacturer_user.id,
        )
        session.add(batch)
        await session.flush()

        stock_package = SerializedPackage(
            package_serial_id="PT-DIST-STOCK-001",
            batch_id=batch.id,
            current_custodian_org_id=distributor_org.id,
            status=PackageStatus.RECEIVED,
            qr_code_data="PT-DIST-STOCK-001",
        )
        inbound_packages = [
            SerializedPackage(
                package_serial_id=f"PT-DIST-INBOUND-{index}",
                batch_id=batch.id,
                current_custodian_org_id=manufacturer.id,
                status=PackageStatus.IN_TRANSIT,
                qr_code_data=f"PT-DIST-INBOUND-{index}",
            )
            for index in (1, 2)
        ]
        session.add_all([stock_package, *inbound_packages])
        await session.flush()

        existing_partner_shipment = Shipment(
            shipment_reference="TEST-DIST-PARTNER-SHIPMENT",
            sender_org_id=distributor_org.id,
            receiver_org_id=wholesaler.id,
            status=ShipmentStatus.RECEIVED,
            declared_quantity=1,
            received_quantity=1,
            created_by=distributor_user.id,
        )
        inbound_shipment = Shipment(
            shipment_reference="TEST-DIST-INBOUND-SHIPMENT",
            sender_org_id=manufacturer.id,
            receiver_org_id=distributor_org.id,
            status=ShipmentStatus.DISPATCHED,
            declared_quantity=2,
            created_by=manufacturer_user.id,
        )
        session.add_all([existing_partner_shipment, inbound_shipment])
        await session.flush()
        session.add_all(
            [
                ShipmentItem(
                    shipment_id=inbound_shipment.id,
                    package_id=package.id,
                    quantity_dispatched=1,
                )
                for package in inbound_packages
            ]
        )
        await session.commit()

    async def override_get_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "test-distributor@example.com",
                    "password": "DistributorTest123!",
                },
            )
            assert login.status_code == 200
            headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

            partners = await client.get(
                "/api/v1/organizations/partners", headers=headers
            )
            assert partners.status_code == 200
            assert [partner["name"] for partner in partners.json()] == [
                "Existing Wholesaler"
            ]
            assert partners.json()[0]["contact_email"] == "wholesaler@example.com"

            pharmacy_directory = await client.get(
                "/api/v1/organizations/pharmacies", headers=headers
            )
            assert pharmacy_directory.status_code == 200
            assert [item["name"] for item in pharmacy_directory.json()] == [
                "Verified Pharmacy"
            ]
            assert (
                pharmacy_directory.json()[0]["address"]
                == "Pharmacy delivery address"
            )

            inventory = await client.get(
                "/api/v1/shipments/inventory", headers=headers
            )
            assert inventory.status_code == 200
            assert [
                package["package_serial_id"] for package in inventory.json()
            ] == ["PT-DIST-STOCK-001"]

            transfer = await client.post(
                "/api/v1/shipments",
                headers=headers,
                json={
                    "receiver_org_id": partners.json()[0]["id"],
                    "package_serial_ids": ["PT-DIST-STOCK-001"],
                    "notes": "Wholesale replenishment",
                },
            )
            assert transfer.status_code == 200, transfer.text
            assert transfer.json()["status"] == "dispatched"
            assert transfer.json()["declared_quantity"] == 1
            duplicate_dispatch = await client.post(
                "/api/v1/shipments",
                headers=headers,
                json={
                    "receiver_org_id": pharmacy_directory.json()[0]["id"],
                    "package_serial_ids": ["PT-DIST-STOCK-001"],
                },
            )
            assert duplicate_dispatch.status_code == 400

            missing_reason = await client.post(
                f"/api/v1/shipments/{inbound_shipment.id}/receive",
                headers=headers,
                json={"actual_quantity_received": 1},
            )
            assert missing_reason.status_code == 400
            assert "reason is required" in missing_reason.json()["detail"]

            distributor_scan = await client.post(
                "/api/v1/verify",
                headers=headers,
                json={"raw_data": "PT-DIST-INBOUND-1"},
            )
            assert distributor_scan.status_code == 200
            assert distributor_scan.json()["is_valid"] is True
            discrepancy = await client.post(
                f"/api/v1/shipments/{inbound_shipment.id}/receive",
                headers=headers,
                json={
                    "actual_quantity_received": 1,
                    "scanned_package_serial_ids": ["PT-DIST-INBOUND-1"],
                    "notes": "One carton was missing on arrival.",
                },
            )
            assert discrepancy.status_code == 200
            assert discrepancy.json()["shipment_status"] == "partially_received"
            assert discrepancy.json()["discrepancy_detected"] is True

            pharmacy_order = await client.post(
                "/api/v1/shipments",
                headers=headers,
                json={
                    "receiver_org_id": pharmacy_directory.json()[0]["id"],
                    "package_serial_ids": ["PT-DIST-INBOUND-1"],
                    "notes": "Pharmacy replenishment",
                },
            )
            assert pharmacy_order.status_code == 200, pharmacy_order.text
            assert pharmacy_order.json()["status"] == "dispatched"

            pharmacy_login = await client.post(
                "/api/v1/auth/login",
                json={
                    "email": "test-pharmacy@example.com",
                    "password": "PharmacyTest123!",
                },
            )
            assert pharmacy_login.status_code == 200
            pharmacy_token = pharmacy_login.json().get("access_token")
            pharmacy_headers = {
                "Authorization": "Bearer " + pharmacy_token
            }
            unverified_package_receipt = await client.post(
                f"/api/v1/shipments/{pharmacy_order.json()['id']}/receive",
                headers=pharmacy_headers,
                json={
                    "actual_quantity_received": 1,
                    "scanned_package_serial_ids": ["PT-DIST-STOCK-001"],
                },
            )
            assert unverified_package_receipt.status_code == 400
            pharmacy_scan = await client.post(
                "/api/v1/verify",
                headers=pharmacy_headers,
                json={"raw_data": "PT-DIST-INBOUND-1"},
            )
            assert pharmacy_scan.status_code == 200
            assert pharmacy_scan.json()["is_valid"] is True
            pharmacy_receipt = await client.post(
                f"/api/v1/shipments/{pharmacy_order.json()['id']}/receive",
                headers=pharmacy_headers,
                json={
                    "actual_quantity_received": 1,
                    "scanned_package_serial_ids": ["PT-DIST-INBOUND-1"],
                },
            )
            assert pharmacy_receipt.status_code == 200, pharmacy_receipt.text
            assert pharmacy_receipt.json()["shipment_status"] == "received"
            assert pharmacy_receipt.json()["tx_reference"]

            suspicious_scan = await client.post(
                "/api/v1/verify",
                headers=headers,
                json={"raw_data": "PT-UNREGISTERED-TEST-CODE"},
            )
            assert suspicious_scan.status_code == 200
            assert suspicious_scan.json()["is_valid"] is False
            dashboard = await client.get(
                "/api/v1/shipments/distributor-dashboard", headers=headers
            )
            assert dashboard.status_code == 200, dashboard.text
            assert dashboard.json()["summary"]["received_batches"] == 1
            assert dashboard.json()["summary"]["outgoing_shipments"] == 3
            assert dashboard.json()["summary"]["pending_pharmacy_receipts"] == 0
            assert dashboard.json()["summary"]["open_alerts"] >= 1
            assert any(
                alert["alert_type"] == "unknown_package"
                for alert in dashboard.json()["alerts"]
            )
    finally:
        app.dependency_overrides.pop(get_db, None)
        await engine.dispose()
