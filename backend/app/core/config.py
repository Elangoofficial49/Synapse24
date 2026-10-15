from typing import List, Union
from pydantic_settings import BaseSettings
from pydantic import Field, field_validator
import os
import json

class Settings(BaseSettings):
    PROJECT_NAME: str = "PharmaTrace API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    
    DATABASE_URL: str = Field(default="sqlite+aiosqlite:///./pharmatrace.db")
    SYNC_DATABASE_URL: str = Field(default="sqlite:///./pharmatrace.db")
    
    SECRET_KEY: str = Field(default="dev_secret_key_pharmatrace_blockchain_supply_chain_2026_super_secure_32_bytes")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 120
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    BLOCKCHAIN_MODE: str = Field(default="test") # 'test' or 'fabric'
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    CORS_ORIGINS: List[str] = ["*"]

    @field_validator("CORS_ORIGINS", mode="before")
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            if v.startswith("[") and v.endswith("]"):
                try:
                    return json.loads(v)
                except Exception:
                    pass
            return [i.strip() for i in v.split(",")]
        elif isinstance(v, list):
            return v
        return ["*"]

    model_config = {
        "env_file": ".env",
        "case_sensitive": True,
        "extra": "ignore"
    }

settings = Settings()

