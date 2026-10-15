from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import create_engine
from app.core.config import settings
from typing import AsyncGenerator

# Setup engine with appropriate parameters
connect_args = {"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}

async_engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    future=True,
    connect_args=connect_args
)

AsyncSessionLocal = async_sessionmaker(
    bind=async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False
)

sync_connect_args = {"check_same_thread": False} if "sqlite" in settings.SYNC_DATABASE_URL else {}
sync_engine = create_engine(settings.SYNC_DATABASE_URL, connect_args=sync_connect_args)
SyncSessionLocal = sessionmaker(bind=sync_engine, autocommit=False, autoflush=False)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

