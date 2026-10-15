from typing import Any, Dict, List
from app.blockchain.interface import BlockchainInterface

class FabricAdapter(BlockchainInterface):
    """
    Hyperledger Fabric Gateway Adapter.
    Requires:
      - Running Hyperledger Fabric v2.5+ network with 'pharmachannel'
      - Deployed Go chaincode 'pharmatrace'
      - Valid X.509 organization identity certificates in connection profile
    """
    def __init__(self, connection_profile_path: str = None):
        self.connection_profile_path = connection_profile_path
        self.is_connected = False

    def _not_configured_error(self):
        return RuntimeError(
            "Hyperledger Fabric network is not configured or reachable. "
            "To run with active Fabric, deploy the network in /blockchain/network, "
            "configure connection profiles, and set BLOCKCHAIN_MODE=fabric in .env"
        )

    async def register_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def register_batch(self, batch_data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def register_package(self, package_data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def initiate_transfer(self, transfer_data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def accept_transfer(self, transfer_data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def partially_accept_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def reject_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def dispute_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def record_pickup(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def record_delivery(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def split_shipment(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def reconcile_quantity(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def flag_suspicious_scan(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def resolve_dispute(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def record_correction(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def recall_batch(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def quarantine_package(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def record_dispensing(self, data: Dict[str, Any]) -> Dict[str, Any]:
        raise self._not_configured_error()

    async def get_custody_history(self, package_id: str) -> List[Dict[str, Any]]:
        raise self._not_configured_error()

    async def health_check(self) -> bool:
        return False

