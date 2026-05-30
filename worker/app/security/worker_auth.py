from fastapi import Header, HTTPException, status

from app.config import get_settings


async def verify_worker_request(authorization: str | None = Header(default=None)) -> None:
    settings = get_settings()
    expected = f"Bearer {settings.worker_shared_secret}"
    if authorization != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid worker authorization.",
        )
