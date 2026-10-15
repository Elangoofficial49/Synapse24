from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.logging_config import setup_logging
from app.db.session import async_engine
from app.db.base import Base

# Routers
from app.api.routes.auth import router as auth_router
from app.api.routes.products import router as products_router
from app.api.routes.qr_verification import router as qr_router
from app.api.routes.shipments import router as shipments_router
from app.api.routes.compliance import router as compliance_router
from app.api.routes.analytics import router as analytics_router
from app.api.routes.organizations import router as orgs_router
from app.api.routes.manufacturer import router as manufacturer_router

setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize SQLite or Postgres tables on startup if not present
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="PharmaTrace Blockchain-backed Pharmaceutical Supply Chain Traceability System",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health", tags=["Health"])
async def health_check():
    return {
        "status": "healthy",
        "service": "PharmaTrace Backend",
        "version": settings.VERSION,
        "blockchain_mode": settings.BLOCKCHAIN_MODE,
        "notice": "Operating with TestBlockchainAdapter. Real Hyperledger Fabric network configuration available."
    }

# Register API routers with /api/v1 prefix
app.include_router(auth_router, prefix=settings.API_V1_STR)
app.include_router(products_router, prefix=settings.API_V1_STR)
app.include_router(qr_router, prefix=settings.API_V1_STR)
app.include_router(shipments_router, prefix=settings.API_V1_STR)
app.include_router(compliance_router, prefix=settings.API_V1_STR)
app.include_router(analytics_router, prefix=settings.API_V1_STR)
app.include_router(orgs_router, prefix=settings.API_V1_STR)
app.include_router(manufacturer_router, prefix=settings.API_V1_STR)
