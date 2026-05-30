import contextvars

import httpx
from mcp.server.auth.provider import AccessToken, TokenVerifier

from app.config import get_settings

_current_user_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "current_user_id", default=None
)


def require_user_id() -> str:
    user_id = _current_user_id.get()
    if not user_id:
        raise RuntimeError("Not authenticated")
    return user_id


class SupabaseTokenVerifier(TokenVerifier):
    async def verify_token(self, token: str) -> AccessToken | None:
        token = token.strip()
        if not token:
            return None
        settings = get_settings()
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{settings.supabase_url}/auth/v1/user",
                headers={
                    "apikey": settings.supabase_anon_key,
                    "Authorization": f"Bearer {token}",
                },
            )
            if r.status_code in (401, 403):
                return None
            r.raise_for_status()
            user = r.json()
        user_id = str(user["id"])
        _current_user_id.set(user_id)
        return AccessToken(token=token, client_id=user_id, scopes=["user"])
