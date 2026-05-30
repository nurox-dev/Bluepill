from typing import Any

from app.services.supabase import SupabaseRestClient


async def write_audit_log(
    supabase: SupabaseRestClient,
    *,
    user_id: str | None,
    actor_type: str,
    event_type: str,
    target_table: str | None = None,
    target_id: str | None = None,
    agent_run_id: str | None = None,
    scheduled_job_id: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> None:
    await supabase.insert(
        "audit_logs",
        {
            "user_id": user_id,
            "actor_type": actor_type,
            "event_type": event_type,
            "target_table": target_table,
            "target_id": target_id,
            "agent_run_id": agent_run_id,
            "scheduled_job_id": scheduled_job_id,
            "metadata": metadata or {},
        },
    )
