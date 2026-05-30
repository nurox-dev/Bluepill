from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.jobs.agent_runs import AgentRunDelivery, process_agent_run
from app.security.supabase_auth import AuthenticatedUser, verify_supabase_user
from app.services.audit import write_audit_log
from app.services.supabase import SupabaseRestClient

router = APIRouter(prefix="/agent", tags=["agent"])


class AgentChatRequest(BaseModel):
    message: str
    conversation_id: str | None = None
    attachments: list[dict[str, Any]] = Field(default_factory=list)
    idempotency_key: str | None = None


def _title_from_message(message: str) -> str:
    collapsed = " ".join(message.split())
    if not collapsed:
        return "Attachment review"
    return collapsed if len(collapsed) <= 60 else f"{collapsed[:57]}..."


def _now_iso() -> str:
    from datetime import UTC, datetime

    return datetime.now(UTC).isoformat()


async def _ensure_conversation(
    supabase: SupabaseRestClient,
    *,
    user_id: str,
    conversation_id: str | None,
    message: str,
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
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conversation not found.",
            )
        return conversation_id

    conversation = await supabase.insert(
        "agent_conversations",
        {
            "user_id": user_id,
            "title": _title_from_message(message),
        },
    )
    return str(conversation["id"])


@router.post("/chat")
async def agent_chat(
    request: AgentChatRequest,
    user: AuthenticatedUser = Depends(verify_supabase_user),
) -> dict[str, Any]:
    message = request.message.strip()
    if not message:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="message is required.",
        )

    supabase = SupabaseRestClient()
    conversation_id = await _ensure_conversation(
        supabase,
        user_id=user.id,
        conversation_id=request.conversation_id,
        message=message,
    )
    message_row = await supabase.insert(
        "agent_messages",
        {
            "user_id": user.id,
            "conversation_id": conversation_id,
            "role": "user",
            "text": message,
            "attachments": request.attachments,
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
            "user_id": user.id,
            "conversation_id": conversation_id,
            "message_id": message_row["id"],
            "run_type": "chat",
            "status": "queued",
            "queue_provider": "fastapi",
            "idempotency_key": request.idempotency_key,
            "input": {
                "message": message,
                "attachments": request.attachments,
            },
        },
    )

    await write_audit_log(
        supabase,
        user_id=user.id,
        actor_type="worker",
        event_type="agent_run.created",
        target_table="agent_runs",
        target_id=str(run["id"]),
        agent_run_id=str(run["id"]),
        metadata={"conversation_id": conversation_id, "entrypoint": "fastapi"},
    )

    try:
        await process_agent_run(
            AgentRunDelivery(user_id=user.id, agent_run_id=str(run["id"])),
        )
    except Exception:
        # process_agent_run records the failed status and error on the run.
        pass

    final_run = await supabase.select_by_id("agent_runs", str(run["id"])) or run
    return {
        "conversation_id": conversation_id,
        "message_id": message_row["id"],
        "agent_run_id": run["id"],
        "status": final_run.get("status", "queued"),
        "result": final_run.get("result") or {},
        "error": final_run.get("error"),
    }
