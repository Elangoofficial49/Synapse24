import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.asyncio
async def test_health_check():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["blockchain_mode"] == "test"

@pytest.mark.asyncio
async def test_login_flow():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Invalid login
        res_fail = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "WrongPassword123"
        })
        assert res_fail.status_code == 401

        # Valid login
        res_ok = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "DevMfr2024!"
        })
        assert res_ok.status_code == 200
        token_data = res_ok.json()
        assert "access_token" in token_data
        assert token_data["user"]["role"] == "manufacturer"

@pytest.mark.asyncio
async def test_qr_verification_unregistered():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/verify", json={
            "raw_data": "https://verify.pharmatrace.org/v1/pkg/PT-FAKE-UNKNOWN-000"
        })
        assert res.status_code == 200
        data = res.json()
        assert data["is_valid"] is False
        assert "ALERT" in data["warning_message"]

@pytest.mark.asyncio
async def test_qr_verification_valid_package():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/verify", json={
            "raw_data": "https://verify.pharmatrace.org/v1/pkg/PT-BATCH-2024-AMX01-0001"
        })
        assert res.status_code == 200
        data = res.json()
        assert data["is_valid"] is True
        assert data["product_name"] == "Amoxicillin Trihydrate Capsules"
        assert data["current_custodian"] == "Apex Bioscience Laboratories"
        assert data["is_expired"] is False
        assert data["is_recalled"] is False

@pytest.mark.asyncio
async def test_two_party_custody_transfer_and_discrepancy():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Login manufacturer
        mfr_res = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "DevMfr2024!"
        })
        mfr_token = mfr_res.json()["access_token"]
        mfr_headers = {"Authorization": f"Bearer {mfr_token}"}

        # Login distributor
        dist_res = await ac.post("/api/v1/auth/login", json={
            "email": "distributor@pharmatrace.dev",
            "password": "DevDist2024!"
        })
        dist_token = dist_res.json()["access_token"]
        dist_user = dist_res.json()["user"]
        dist_headers = {"Authorization": f"Bearer {dist_token}"}

        # 1. Manufacturer creates and dispatches shipment of 5 packages
        pkg_ids = [f"PT-BATCH-2024-AMX01-{i:04d}" for i in range(11, 16)]
        create_res = await ac.post("/api/v1/shipments", json={
            "receiver_org_id": dist_user["organization_id"],
            "package_serial_ids": pkg_ids,
            "notes": "Consignment of 5 Amoxicillin units for Regional Depot"
        }, headers=mfr_headers)
        assert create_res.status_code == 200, create_res.text
        shipment = create_res.json()
        shipment_id = shipment["id"]
        assert shipment["declared_quantity"] == 5
        assert shipment["status"] == "dispatched"

        # 2. Distributor confirms receipt of only 4 packages (discrepancy demo)
        rcv_res = await ac.post(f"/api/v1/shipments/{shipment_id}/receive", json={
            "actual_quantity_received": 4,
            "notes": "Discrepancy: Box seal damaged, only 4 units present."
        }, headers=dist_headers)
        assert rcv_res.status_code == 200
        rcv_data = rcv_res.json()
        assert rcv_data["discrepancy_detected"] is True
        assert rcv_data["shipment_status"] == "partially_received"
        assert rcv_data["dispute_id"] is not None

        # 3. Check that dispute is registered
        disputes_res = await ac.get("/api/v1/disputes", headers=dist_headers)
        assert disputes_res.status_code == 200
        disputes = disputes_res.json()
        assert any(d["shipment_id"] == shipment_id for d in disputes)
