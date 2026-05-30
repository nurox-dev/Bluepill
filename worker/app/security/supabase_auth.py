from dataclasses import dataclass

from fastapi import Header, HTTPException, status

from app.services.supabase import SupabaseRestClient


@dataclass(frozen=True)
class AuthenticatedUser:
    id: str


async def verify_supabase_user(
    authorization: str | None = Header(default=None),
) -> AuthenticatedUser:
    parts = (authorization or "").strip().split()
    token = parts[1] if len(parts) == 2 and parts[0].lower() == "bearer" else ""
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Supabase user token.",
        )

    user = await SupabaseRestClient().get_user(token)
    if not user or not user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Supabase user token.",
        )

    return AuthenticatedUser(id=str(user["id"]))
