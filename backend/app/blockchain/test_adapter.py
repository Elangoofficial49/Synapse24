import uuid
import hashlib
import json
from datetime import datetime
from typing import Any, Dict, List
from app.blockchain.interface import BlockchainInterface

class TestBlockchainAdapter(BlockchainInterface):
    """
    Test/Development Blockchain Adapter.
    - Explicitly marks all operations with status='test_mode'
    - Produces realistic transaction IDs prefixed with 'TX-TEST-'
    - Maintains in-memory verifiable ledger history for test scenarios
    - Never masquerades as a live Hyperledger Fabric transaction
    """

    def __init__(self):
        self._ledger_events: Dict[str, List[Dict[str, Any]]] = {}

    def _generate_tx(self, function_name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        payload_str = json.dumps(payload, sort_keys=True, default=str)
        payload_hash = hashlib.sha256(payload_str.encode()).hexdigest()
        tx_id = f"TX-TEST-{uuid.uuid4().hex[:12].upper()}"
        
        tx_record = {
            "tx_id": tx_id,
            "status": "test_mode",
            "blockchain_mode": "test",
            "channel": "pharmachannel",
            "chaincode": "pharmatrace",
            "function": function_name,
            "payload_hash": payload_hash,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "is_on_chain": False, # Explicit: not a real on-chain Fabric commitment
            "notice": "Simulated transaction generated in test blockchain mode. Real Hyperledger Fabric network required for immutable on-chain confirmation."
        }
        return tx_record

    async def register_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("registerProduct", product_data)

    async def register_batch(self, batch_data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("registerBatch", batch_data)

    async def register_package(self, package_data: Dict[str, Any]) -> Dict[str, Any]:
        tx = self._generate_tx("registerPackage", package_data)
        pkg_id = package_data.get("package_serial_id")
        if pkg_id:
            if pkg_id not in self._ledger_events:
                self._ledger_events[pkg_id] = []
            self._ledger_events[pkg_id].append({**package_data, **tx, "event_type": "MANUFACTURED"})
        return tx

    async def initiate_transfer(self, transfer_data: Dict[str, Any]) -> Dict[str, Any]:
        tx = self._generate_tx("initiateTransfer", transfer_data)
        for pkg_id in transfer_data.get("package_serial_ids", []):
            if pkg_id in self._ledger_events:
                self._ledger_events[pkg_id].append({**transfer_data, **tx, "event_type": "DISPATCHED"})
        return tx

    async def accept_transfer(self, transfer_data: Dict[str, Any]) -> Dict[str, Any]:
        tx = self._generate_tx("acceptTransfer", transfer_data)
        for pkg_id in transfer_data.get("package_serial_ids", []):
            if pkg_id in self._ledger_events:
                self._ledger_events[pkg_id].append({**transfer_data, **tx, "event_type": "RECEIVED"})
        return tx

    async def partially_accept_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("partiallyAcceptTransfer", data)

    async def reject_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("rejectTransfer", data)

    async def dispute_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("disputeTransfer", data)

    async def record_pickup(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("recordPickup", data)

    async def record_delivery(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("recordDelivery", data)

    async def split_shipment(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("splitShipment", data)

    async def reconcile_quantity(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("reconcileQuantity", data)

    async def flag_suspicious_scan(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("flagSuspiciousScan", data)

    async def resolve_dispute(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("resolveDispute", data)

    async def record_correction(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("recordCorrection", data)

    async def recall_batch(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("recallBatch", data)

    async def quarantine_package(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("quarantinePackage", data)

    async def record_dispensing(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return self._generate_tx("recordDispensing", data)

    async def get_custody_history(self, package_id: str) -> List[Dict[str, Any]]:
        return self._ledger_events.get(package_id, [])

    async def health_check(self) -> bool:
        return True

