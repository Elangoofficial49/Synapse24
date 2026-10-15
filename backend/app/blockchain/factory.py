from app.core.config import settings
from app.blockchain.interface import BlockchainInterface
from app.blockchain.test_adapter import TestBlockchainAdapter
from app.blockchain.fabric_adapter import FabricAdapter

_test_adapter_instance = None

def get_blockchain_adapter() -> BlockchainInterface:
    global _test_adapter_instance
    if settings.BLOCKCHAIN_MODE.lower() == "fabric":
        return FabricAdapter()
    
    if _test_adapter_instance is None:
        _test_adapter_instance = TestBlockchainAdapter()
    return _test_adapter_instance

