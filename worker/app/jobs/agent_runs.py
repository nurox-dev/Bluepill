from datetime import UTC, datetime
from typing import Any

from pydantic import BaseModel

from app.agents.bluepill_agent import run_bluepill_agent
from app.services.audit import write_audit_log
from app.services.context import load_user_context
from app.services.supabase import SupabaseRestClient
from app.tools.memory import search_memory


class AgentRunDelivery(BaseModel):
    user_id: str
    agent_run_id: str
    approval_id: str | None = None


def _now() -> str:
    return datetime.now(UTC).isoformat()


async def _load_conversation_history(
    supabase: SupabaseRestClient,
    *,
    user_id: str,
    conversation_id: str | None,
) -> list[dict[str, Any]]:
    if not conversation_id:
        return []

    rows = await supabase.select(
        "agent_messages",
        {
            "user_id": f"eq.{user_id}",
            "conversation_id": f"eq.{conversation_id}",
            "select": "role,text,attachments,created_at",
            "order": "created_at.desc",
            "limit": "24",
        },
    )
    rows.reverse()
    return rows


async def process_agent_run(delivery: AgentRunDelivery) -> None:
    supabase = SupabaseRestClient()
    run = await supabase.select_by_id("agent_runs", delivery.agent_run_id)
    if not run:
        raise ValueError(f"agent_run not found: {delivery.agent_run_id}")

    await supabase.update_by_id(
        "agent_runs",
        delivery.agent_run_id,
        {"status": "running", "started_at": _now(), "updated_at": _now()},
    )
    await write_audit_log(
        supabase,
        user_id=delivery.user_id,
        actor_type="worker",
        event_type="agent_run.started",
        target_table="agent_runs",
        target_id=delivery.agent_run_id,
        agent_run_id=delivery.agent_run_id,
    )

    try:
        input_payload: dict[str, Any] = run.get("input") or {}
        message = str(input_payload.get("message") or "")
        attachments = input_payload.get("attachments")
        if not isinstance(attachments, list):
            attachments = []
        conversation_id = run.get("conversation_id")
        context = await load_user_context(supabase, delivery.user_id)
        history = await _load_conversation_history(
            supabase,
            user_id=delivery.user_id,
            conversation_id=conversation_id,
        )
        memories = await search_memory(supabase, delivery.user_id, message)
        result = await run_bluepill_agent(
            message=message,
            user_context=context,
            memories=memories,
            conversation_history=history,
            attachments=attachments,
        )

        if conversation_id:
            await supabase.insert(
                "agent_messages",
                {
                    "user_id": delivery.user_id,
                    "conversation_id": conversation_id,
                    "role": "assistant",
                    "text": result["text"],
                    "attachments": [],
                },
            )
            await supabase.update_by_id(
                "agent_conversations",
                conversation_id,
                {"updated_at": _now()},
            )

        await supabase.update_by_id(
            "agent_runs",
            delivery.agent_run_id,
            {
                "status": "completed",
                "result": result,
                "tool_names": result.get("tool_names", []),
                "completed_at": _now(),
                "updated_at": _now(),
            },
        )
        await write_audit_log(
            supabase,
            user_id=delivery.user_id,
            actor_type="worker",
            event_type="agent_run.completed",
            target_table="agent_runs",
            target_id=delivery.agent_run_id,
            agent_run_id=delivery.agent_run_id,
        )
    except Exception as error:
        await supabase.update_by_id(
            "agent_runs",
            delivery.agent_run_id,
            {
                "status": "failed",
                "error": str(error),
                "completed_at": _now(),
                "updated_at": _now(),
            },
        )
        await write_audit_log(
            supabase,
            user_id=delivery.user_id,
            actor_type="worker",
            event_type="agent_run.failed",
            target_table="agent_runs",
            target_id=delivery.agent_run_id,
            agent_run_id=delivery.agent_run_id,
            metadata={"error": str(error)},
        )
        raise
