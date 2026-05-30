from datetime import UTC, datetime

from pydantic import BaseModel

from app.jobs.agent_runs import AgentRunDelivery, process_agent_run
from app.services.audit import write_audit_log
from app.services.supabase import SupabaseRestClient


class ScheduledJobDelivery(BaseModel):
    user_id: str
    scheduled_job_id: str


def _now() -> str:
    return datetime.now(UTC).isoformat()


async def process_scheduled_job(delivery: ScheduledJobDelivery) -> None:
    supabase = SupabaseRestClient()
    job = await supabase.select_by_id("scheduled_jobs", delivery.scheduled_job_id)
    if not job:
        raise ValueError(f"scheduled_job not found: {delivery.scheduled_job_id}")

    await supabase.update_by_id(
        "scheduled_jobs",
        delivery.scheduled_job_id,
        {"status": "running", "started_at": _now(), "updated_at": _now()},
    )
    await write_audit_log(
        supabase,
        user_id=delivery.user_id,
        actor_type="worker",
        event_type="scheduled_job.started",
        target_table="scheduled_jobs",
        target_id=delivery.scheduled_job_id,
        scheduled_job_id=delivery.scheduled_job_id,
    )

    agent_run_id = job.get("agent_run_id")
    if agent_run_id:
        await process_agent_run(
            AgentRunDelivery(
                user_id=delivery.user_id,
                agent_run_id=agent_run_id,
            ),
        )

    await supabase.update_by_id(
        "scheduled_jobs",
        delivery.scheduled_job_id,
        {"status": "completed", "completed_at": _now(), "updated_at": _now()},
    )
    await write_audit_log(
        supabase,
        user_id=delivery.user_id,
        actor_type="worker",
        event_type="scheduled_job.completed",
        target_table="scheduled_jobs",
        target_id=delivery.scheduled_job_id,
        scheduled_job_id=delivery.scheduled_job_id,
    )
