from abc import ABC, abstractmethod
from typing import Any, Dict, Optional, List

class BlockchainInterface(ABC):
    @abstractmethod
    async def register_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        """Record newly registered pharmaceutical product on ledger"""
        pass

    @abstractmethod
    async def register_batch(self, batch_data: Dict[str, Any]) -> Dict[str, Any]:
        """Record newly registered batch on ledger"""
        pass

    @abstractmethod
    async def register_package(self, package_data: Dict[str, Any]) -> Dict[str, Any]:
        """Record serialized package identity and initial state"""
        pass

    @abstractmethod
    async def initiate_transfer(self, transfer_data: Dict[str, Any]) -> Dict[str, Any]:
        """Record transfer initiation with declared quantities"""
        pass

    @abstractmethod
    async def accept_transfer(self, transfer_data: Dict[str, Any]) -> Dict[str, Any]:
        """Record receiver full acceptance of shipment"""
        pass

    @abstractmethod
    async def partially_accept_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record partial acceptance and discrepancy on ledger"""
        pass

    @abstractmethod
    async def reject_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record rejection of shipment"""
        pass

    @abstractmethod
    async def dispute_transfer(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record formal dispute with expected vs actual discrepancies"""
        pass

    @abstractmethod
    async def record_pickup(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record transporter custody pickup"""
        pass

    @abstractmethod
    async def record_delivery(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record delivery handover event"""
        pass

    @abstractmethod
    async def split_shipment(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record parent shipment split into reconciled child shipments"""
        pass

    @abstractmethod
    async def reconcile_quantity(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record formal reconciliation event"""
        pass

    @abstractmethod
    async def flag_suspicious_scan(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record flagged suspicious scan or state violation"""
        pass

    @abstractmethod
    async def resolve_dispute(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record dispute resolution on ledger"""
        pass

    @abstractmethod
    async def record_correction(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Append-only correction event preserving historical integrity"""
        pass

    @abstractmethod
    async def recall_batch(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record batch recall status on ledger"""
        pass

    @abstractmethod
    async def quarantine_package(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record package quarantine status"""
        pass

    @abstractmethod
    async def record_dispensing(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record final dispensing to patient/customer"""
        pass

    @abstractmethod
    async def get_custody_history(self, package_id: str) -> List[Dict[str, Any]]:
        """Retrieve verified ledger history for a serialized package"""
        pass

    @abstractmethod
    async def health_check(self) -> bool:
        """Check connection to blockchain network"""
        pass

