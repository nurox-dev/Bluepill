from typing import Any

from app.services.supabase import SupabaseRestClient


async def search_memory(
    supabase: SupabaseRestClient,
    user_id: str,
    query: str,
) -> list[dict[str, Any]]:
    if not query.strip():
        return []

    # Embedding generation is intentionally separate from this scaffold.
    # Once wired, pass the generated vector to match_agent_memory.
    return []
