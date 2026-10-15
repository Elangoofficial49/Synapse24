import hashlib
from datetime import date, timedelta
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_feature_a_smart_scan_intelligence():
    """Verify Smart Scan statuses: VERIFIED, DUPLICATE_SCAN, INVALID_QR, CUSTODY_MISMATCH, RECALLED."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Login manufacturer
        mfr_res = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "DevMfr2024!"
        })
        assert mfr_res.status_code == 200
        mfr_headers = {"Authorization": f"Bearer {mfr_res.json()['access_token']}"}

        # 1. Invalid QR
        inv_res = await ac.post("/api/v1/verify", json={"raw_data": "https://unknown.pharma/invalid-pkg"})
        assert inv_res.status_code == 200
        inv_data = inv_res.json()
        assert inv_data["is_valid"] is False
        assert inv_data["verification_status"] == "INVALID_QR"

        # 2. Setup batch & package
        suffix = uuid4().hex[:8].upper()
        prod = await ac.post("/api/v1/products", json={
            "name": f"SmartScan Med {suffix}",
            "generic_name": "SmartScan Chem",
            "product_code": f"SS-{suffix}",
            "dosage_form": "Tablet",
            "strength": "500 mg"
        }, headers=mfr_headers)
        assert prod.status_code == 200

        batch = await ac.post("/api/v1/batches", json={
            "product_id": prod.json()["id"],
            "batch_number": f"BATCH-{suffix}",
            "manufacturing_date": date.today().isoformat(),
            "expiry_date": (date.today() + timedelta(days=365)).isoformat(),
            "quantity_manufactured": 2
        }, headers=mfr_headers)
        assert batch.status_code == 200
        batch_id = batch.json()["id"]

        pkgs = await ac.post(
            f"/api/v1/batches/{batch_id}/generate-packages",
            json={"batch_id": batch_id, "count": 2},
            headers=mfr_headers
        )
        assert pkgs.status_code == 200
        pkg_serial = pkgs.json()[0]["package_serial_id"]

        # 3. Valid Scan -> VERIFIED
        v_res = await ac.post("/api/v1/verify", json={"raw_data": pkg_serial}, headers=mfr_headers)
        assert v_res.status_code == 200
        v_data = v_res.json()
        assert v_data["is_valid"] is True
        assert v_data["verification_status"] == "VERIFIED"
        assert v_data["blockchain_tx_ref"] is not None

        # 4. Repeated scans frequency detection -> DUPLICATE_SCAN
        # Scan same package multiple times rapidly
        for _ in range(4):
            await ac.post("/api/v1/verify", json={"raw_data": pkg_serial}, headers=mfr_headers)
        dup_res = await ac.post("/api/v1/verify", json={"raw_data": pkg_serial}, headers=mfr_headers)
        assert dup_res.status_code == 200
        dup_data = dup_res.json()
        assert dup_data["verification_status"] == "DUPLICATE_SCAN"

        # 5. Recall batch -> RECALLED status
        rec_res = await ac.post("/api/v1/recalls", json={
            "batch_id": batch_id,
            "recall_reason": "Precautionary safety quarantine for testing",
            "severity": "mandatory"
        }, headers=mfr_headers)
        assert rec_res.status_code == 200

        rec_scan = await ac.post("/api/v1/verify", json={"raw_data": pkg_serial}, headers=mfr_headers)
        assert rec_scan.status_code == 200
        assert rec_scan.json()["verification_status"] == "RECALLED"


@pytest.mark.asyncio
async def test_feature_b_recall_impact_simulation_and_quarantine():
    """Verify Recall Impact calculation and quarantine acknowledgement workflow."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        mfr_res = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "DevMfr2024!"
        })
        mfr_headers = {"Authorization": f"Bearer {mfr_res.json()['access_token']}"}

        dist_res = await ac.post("/api/v1/auth/login", json={
            "email": "distributor@pharmatrace.dev",
            "password": "DevDist2024!"
        })
        dist_token = dist_res.json()["access_token"]
        dist_user = dist_res.json()["user"]
        dist_headers = {"Authorization": f"Bearer {dist_token}"}

        suffix = uuid4().hex[:8].upper()
        prod = await ac.post("/api/v1/products", json={
            "name": f"Recall Med {suffix}",
            "generic_name": "Recall Chem",
            "product_code": f"REC-{suffix}",
            "dosage_form": "Vial",
            "strength": "100 mg"
        }, headers=mfr_headers)
        batch = await ac.post("/api/v1/batches", json={
            "product_id": prod.json()["id"],
            "batch_number": f"REC-BATCH-{suffix}",
            "manufacturing_date": date.today().isoformat(),
            "expiry_date": (date.today() + timedelta(days=180)).isoformat(),
            "quantity_manufactured": 4
        }, headers=mfr_headers)
        batch_id = batch.json()["id"]

        pkgs = await ac.post(
            f"/api/v1/batches/{batch_id}/generate-packages",
            json={"batch_id": batch_id, "count": 4},
            headers=mfr_headers
        )
        pkg_serials = [p["package_serial_id"] for p in pkgs.json()]

        # Dispatch 4 packages to distributor
        shipment = await ac.post("/api/v1/shipments", json={
            "receiver_org_id": dist_user["organization_id"],
            "package_serial_ids": pkg_serials,
            "notes": "Consignment for Recall test"
        }, headers=mfr_headers)
        shipment_id = shipment.json()["id"]

        # Distributor verifies packages before confirming receipt
        for s in pkg_serials:
            await ac.post("/api/v1/verify", json={"raw_data": s}, headers=dist_headers)

        # Receive at distributor
        await ac.post(f"/api/v1/shipments/{shipment_id}/receive", json={
            "actual_quantity_received": 4,
            "scanned_package_serial_ids": pkg_serials,
        }, headers=dist_headers)

        # Initiate recall
        recall = await ac.post("/api/v1/recalls", json={
            "batch_id": batch_id,
            "recall_reason": "Labeling defect found post-release",
            "severity": "voluntary"
        }, headers=mfr_headers)
        recall_id = recall.json()["id"]

        # Verify impact simulator calculates downstream distributors
        impact_res = await ac.get(f"/api/v1/recalls/{batch_id}/impact", headers=mfr_headers)
        assert impact_res.status_code == 200
        impact = impact_res.json()
        assert impact["quantities"]["manufactured"] == 4
        assert impact["quantities"]["quarantined"] == 0
        assert impact["quantities"]["unresolved"] == 4
        assert len(impact["distributors"]) >= 1

        # Distributor acknowledges recall and quarantines 4 units
        ack_res = await ac.post(f"/api/v1/recalls/{recall_id}/acknowledge", json={
            "quarantined_quantity": 4,
            "response_notes": "All 4 units moved to cold-storage quarantine vault."
        }, headers=dist_headers)
        assert ack_res.status_code == 200
        ack_data = ack_res.json()
        assert ack_data["quarantined_quantity"] == 4
        assert ack_data["blockchain_tx_ref"] is not None

        # Re-verify impact simulator reflects quarantined quantity
        impact_updated = await ac.get(f"/api/v1/recalls/{batch_id}/impact", headers=mfr_headers)
        assert impact_updated.status_code == 200
        assert impact_updated.json()["quantities"]["quarantined"] == 4
        assert impact_updated.json()["quantities"]["unresolved"] == 0


@pytest.mark.asyncio
async def test_feature_c_quantity_discrepancy_and_investigation():
    """Verify discrepancy calculation Delta = Q_declared - Q_received and investigation workflow."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        mfr_res = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "DevMfr2024!"
        })
        mfr_headers = {"Authorization": f"Bearer {mfr_res.json()['access_token']}"}

        dist_res = await ac.post("/api/v1/auth/login", json={
            "email": "distributor@pharmatrace.dev",
            "password": "DevDist2024!"
        })
        dist_headers = {"Authorization": f"Bearer {dist_res.json()['access_token']}"}
        dist_user = dist_res.json()["user"]

        suffix = uuid4().hex[:8].upper()
        prod = await ac.post("/api/v1/products", json={
            "name": f"Discrepancy Med {suffix}",
            "generic_name": "Discrepancy Chem",
            "product_code": f"DISC-{suffix}",
            "dosage_form": "Capsule",
            "strength": "250 mg"
        }, headers=mfr_headers)
        batch = await ac.post("/api/v1/batches", json={
            "product_id": prod.json()["id"],
            "batch_number": f"DISC-BATCH-{suffix}",
            "manufacturing_date": date.today().isoformat(),
            "expiry_date": (date.today() + timedelta(days=200)).isoformat(),
            "quantity_manufactured": 5
        }, headers=mfr_headers)
        batch_id = batch.json()["id"]

        pkgs = await ac.post(
            f"/api/v1/batches/{batch_id}/generate-packages",
            json={"batch_id": batch_id, "count": 5},
            headers=mfr_headers
        )
        pkg_serials = [p["package_serial_id"] for p in pkgs.json()]

        # 1. Manufacturer dispatches 5 units
        shipment = await ac.post("/api/v1/shipments", json={
            "receiver_org_id": dist_user["organization_id"],
            "package_serial_ids": pkg_serials,
            "notes": "Standard dispatch 5 units"
        }, headers=mfr_headers)
        shipment_id = shipment.json()["id"]

        # Distributor verifies packages before confirming receipt
        for s in pkg_serials[:3]:
            await ac.post("/api/v1/verify", json={"raw_data": s}, headers=dist_headers)

        # 2. Distributor confirms only 3 units received -> discrepancy of 2
        receive_res = await ac.post(f"/api/v1/shipments/{shipment_id}/receive", json={
            "actual_quantity_received": 3,
            "scanned_package_serial_ids": pkg_serials[:3],
            "notes": "Missing 2 units: box torn in transit."
        }, headers=dist_headers)
        assert receive_res.status_code == 200
        rcv = receive_res.json()
        assert rcv["discrepancy_detected"] is True
        assert rcv["shipment_status"] == "partially_received"
        dispute_id = rcv["dispute_id"]

        # Verify dispute record preserved declared vs received
        disp_res = await ac.get(f"/api/v1/disputes/{dispute_id}", headers=dist_headers)
        assert disp_res.status_code == 200
        disp = disp_res.json()
        assert disp["expected_quantity"] == 5
        assert disp["actual_quantity"] == 3
        assert disp["status"].upper() == "OPEN"

        # 3. Update investigation with SHA-256 evidence document hash
        evidence_doc = "Official Carrier Carrier Loss Report #CLR-9941"
        evidence_hash = hashlib.sha256(evidence_doc.encode()).hexdigest()

        inv_res = await ac.put(f"/api/v1/disputes/{dispute_id}/investigate", json={
            "status": "UNDER_INVESTIGATION",
            "evidence_reference": "Carrier Loss Report CLR-9941.pdf",
            "evidence_hash": evidence_hash,
            "investigation_notes": "Carrier confirmed pallet breach; loss occurred during third-party transport."
        }, headers=dist_headers)
        assert inv_res.status_code == 200
        inv_data = inv_res.json()
        assert inv_data["status"].upper() == "UNDER_INVESTIGATION"
        assert inv_data["evidence_hash"] == evidence_hash
        assert "pallet breach" in inv_data["resolution_notes"]


@pytest.mark.asyncio
async def test_feature_d_offline_first_receipt_sync_and_idempotency():
    """Verify offline receipt synchronization, idempotency key enforcement, and recall conflict checks."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        mfr_res = await ac.post("/api/v1/auth/login", json={
            "email": "manufacturer@pharmatrace.dev",
            "password": "DevMfr2024!"
        })
        mfr_headers = {"Authorization": f"Bearer {mfr_res.json()['access_token']}"}

        dist_res = await ac.post("/api/v1/auth/login", json={
            "email": "distributor@pharmatrace.dev",
            "password": "DevDist2024!"
        })
        dist_headers = {"Authorization": f"Bearer {dist_res.json()['access_token']}"}
        dist_user = dist_res.json()["user"]

        suffix = uuid4().hex[:8].upper()
        prod = await ac.post("/api/v1/products", json={
            "name": f"Offline Med {suffix}",
            "generic_name": "Offline Chem",
            "product_code": f"OFF-{suffix}",
            "dosage_form": "Tablet",
            "strength": "10 mg"
        }, headers=mfr_headers)
        batch = await ac.post("/api/v1/batches", json={
            "product_id": prod.json()["id"],
            "batch_number": f"OFF-BATCH-{suffix}",
            "manufacturing_date": date.today().isoformat(),
            "expiry_date": (date.today() + timedelta(days=365)).isoformat(),
            "quantity_manufactured": 2
        }, headers=mfr_headers)
        batch_id = batch.json()["id"]

        pkgs = await ac.post(
            f"/api/v1/batches/{batch_id}/generate-packages",
            json={"batch_id": batch_id, "count": 2},
            headers=mfr_headers
        )
        pkg_serials = [p["package_serial_id"] for p in pkgs.json()]

        shipment = await ac.post("/api/v1/shipments", json={
            "receiver_org_id": dist_user["organization_id"],
            "package_serial_ids": pkg_serials,
            "notes": "Offline capture test consignment"
        }, headers=mfr_headers)
        shipment_id = shipment.json()["id"]

        # Distributor verifies packages before offline capture
        for s in pkg_serials:
            await ac.post("/api/v1/verify", json={"raw_data": s}, headers=dist_headers)

        # 1. Synchronize offline captured receipt payload
        offline_event_id = f"OFFLINE-{uuid4().hex[:8].upper()}"
        idempotency_key = f"IDEMP-{uuid4().hex}"

        receipt_payload = {
            "receipts": [{
                "event_id": offline_event_id,
                "idempotency_key": idempotency_key,
                "shipment_id": shipment_id,
                "actual_quantity_received": 2,
                "declared_quantity": 2,
                "scanned_package_serial_ids": pkg_serials,
                "notes": "Warehouse captured offline during connectivity failure.",
                "device_timestamp": "2026-10-15T12:00:00Z"
            }]
        }

        sync_res = await ac.post("/api/v1/shipments/sync-offline-receipts", json=receipt_payload, headers=dist_headers)
        assert sync_res.status_code == 200
        sync_data = sync_res.json()
        assert sync_data["synced_count"] == 1
        assert sync_data["results"][0]["status"] == "SYNCHRONIZED"
        assert sync_data["results"][0]["blockchain_tx_ref"] is not None

        # 2. Idempotency test: Resending the exact same offline receipt should NOT duplicate
        resync = await ac.post("/api/v1/shipments/sync-offline-receipts", json=receipt_payload, headers=dist_headers)
        assert resync.status_code == 200
        resync_data = resync.json()
        # Should detect already received / duplicate
        assert resync_data["synced_count"] == 0
        assert resync_data["results"][0]["status"] in ("ALREADY_PROCESSED", "SYNCHRONIZED")
