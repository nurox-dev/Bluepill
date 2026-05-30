from datetime import UTC, datetime
from typing import Any

from app.jobs.agent_runs import AgentRunDelivery, process_agent_run
from app.services.audit import write_audit_log
from app.services.supabase import SupabaseRestClient

SUPPORTED_CRON_TASKS = {"agent_prompt", "noop"}


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


def is_supported_cron_task(task: str) -> bool:
    return task.strip().lower() in SUPPORTED_CRON_TASKS


async def _ensure_conversation(
    supabase: SupabaseRestClient,
    *,
    user_id: str,
    conversation_id: str | None,
    title: str,
) -> str:
    if conversation_id:
        rows = await supabase.select(
            "agent_conversations",
            {
                "id": f"eq.{conversation_id}",
                "user_id": f"eq.{user_id}",
                "select": "id",
                "limit": "1",
            },
        )
        if not rows:
            raise ValueError("Cron job conversation_id was not found for this user.")
        return conversation_id

    conversation = await supabase.insert(
        "agent_conversations",
        {
            "user_id": user_id,
            "title": title[:80] or "Scheduled agent task",
        },
    )
    return str(conversation["id"])


async def _run_agent_prompt(
    supabase: SupabaseRestClient,
    *,
    job: dict[str, Any],
    execution_id: str,
) -> dict[str, Any]:
    payload = job.get("payload") or {}
    if not isinstance(payload, dict):
        payload = {}

    message = str(payload.get("message") or payload.get("prompt") or "").strip()
    if not message:
        raise ValueError(
            "agent_prompt cron jobs require payload.message or payload.prompt."
        )

    attachments = payload.get("attachments")
    if not isinstance(attachments, list):
        attachments = []

    conversation_id_value = payload.get("conversation_id")
    conversation_id = (
        str(conversation_id_value).strip() if conversation_id_value else None
    )
    conversation_id = await _ensure_conversation(
        supabase,
        user_id=str(job["user_id"]),
        conversation_id=conversation_id,
        title=str(job.get("name") or "Scheduled agent task"),
    )

    message_row = await supabase.insert(
        "agent_messages",
        {
            "user_id": job["user_id"],
            "conversation_id": conversation_id,
            "role": "user",
            "text": message,
            "attachments": attachments,
        },
    )
    await supabase.update_by_id(
        "agent_conversations",
        conversation_id,
        {"updated_at": _now_iso()},
    )

    run = await supabase.insert(
        "agent_runs",
        {
            "user_id": job["user_id"],
            "conversation_id": conversation_id,
            "message_id": message_row["id"],
            "run_type": "cron",
            "status": "queued",
            "queue_provider": "cron",
            "input": {
                "message": message,
                "attachments": attachments,
                "cron_job_id": job["id"],
                "cron_execution_id": execution_id,
            },
        },
    )
    agent_run_id = str(run["id"])
    await supabase.update_by_id(
        "cron_job_executions",
        execution_id,
        {"agent_run_id": agent_run_id, "updated_at": _now_iso()},
    )
    await write_audit_log(
        supabase,
        user_id=str(job["user_id"]),
        actor_type="worker",
        event_type="cron_job.agent_run.created",
        target_table="agent_runs",
        target_id=agent_run_id,
        agent_run_id=agent_run_id,
        metadata={"cron_job_id": job["id"], "cron_execution_id": execution_id},
    )

    await process_agent_run(
        AgentRunDelivery(user_id=str(job["user_id"]), agent_run_id=agent_run_id),
    )
    final_run = await supabase.select_by_id("agent_runs", agent_run_id) or run
    if final_run.get("status") != "completed":
        raise RuntimeError(
            f"Agent run finished with status {final_run.get('status')}: "
            f"{final_run.get('error') or 'no error detail'}"
        )

    return {
        "agent_run_id": agent_run_id,
        "conversation_id": conversation_id,
        "agent_status": final_run.get("status"),
        "result": final_run.get("result") or {},
    }


async def execute_cron_task(
    supabase: SupabaseRestClient,
    *,
    job: dict[str, Any],
    execution_id: str,
) -> dict[str, Any]:
    task = str(job.get("task") or "").strip().lower()

    if task == "noop":
        return {
            "message": "No-op cron task completed.",
            "cron_job_id": job.get("id"),
            "cron_execution_id": execution_id,
        }

    if task == "agent_prompt":
        return await _run_agent_prompt(
            supabase,
            job=job,
            execution_id=execution_id,
        )

    raise ValueError(f"Unsupported cron task: {task}")
