from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.jobs.cron_scheduler import compute_next_run_at, validate_cron_schedule
from app.jobs.cron_scheduler import validate_timezone
from app.jobs.cron_tasks import SUPPORTED_CRON_TASKS, is_supported_cron_task
from app.security.supabase_auth import AuthenticatedUser, verify_supabase_user
from app.services.audit import write_audit_log
from app.services.supabase import SupabaseRestClient

router = APIRouter(prefix="/cron", tags=["cron"])


class CronJobCreateRequest(BaseModel):
    name: str
    schedule: str = Field(description="Cron expression, for example: 0 9 * * *")
    task: str
    payload: dict[str, Any] = Field(default_factory=dict)
    enabled: bool = True
    timezone: str = "UTC"
    max_retries: int = Field(default=0, ge=0, le=10)
    timeout_seconds: int = Field(default=300, ge=1, le=3600)
    retry_delay_seconds: int = Field(default=30, ge=0, le=3600)
    idempotency_key: str | None = None


class CronJobUpdateRequest(BaseModel):
    name: str | None = None
    schedule: str | None = None
    task: str | None = None
    payload: dict[str, Any] | None = None
    enabled: bool | None = None
    timezone: str | None = None
    max_retries: int | None = Field(default=None, ge=0, le=10)
    timeout_seconds: int | None = Field(default=None, ge=1, le=3600)
    retry_delay_seconds: int | None = Field(default=None, ge=0, le=3600)


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


def _normalize_name(name: str | None) -> str:
    normalized = " ".join((name or "").strip().split())
    if not normalized:
        raise ValueError("name is required.")
    if len(normalized) > 120:
        raise ValueError("name must be 120 characters or fewer.")
    return normalized


def _normalize_task(task: str | None) -> str:
    normalized = (task or "").strip().lower()
    if not normalized:
        raise ValueError("task is required.")
    if not is_supported_cron_task(normalized):
        supported = ", ".join(sorted(SUPPORTED_CRON_TASKS))
        raise ValueError(f"Unsupported task. Supported tasks: {supported}.")
    return normalized


def _validate_or_422(callback: Any) -> Any:
    try:
        return callback()
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(error),
        ) from error


async def _get_owned_job(
    supabase: SupabaseRestClient,
    *,
    user_id: str,
    job_id: str,
) -> dict[str, Any]:
    rows = await supabase.select(
        "cron_jobs",
        {
            "id": f"eq.{job_id}",
            "user_id": f"eq.{user_id}",
            "select": "*",
            "limit": "1",
        },
    )
    if not rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cron job not found.",
        )
    return rows[0]


@router.get("/jobs")
async def list_cron_jobs(
    user: AuthenticatedUser = Depends(verify_supabase_user),
) -> dict[str, Any]:
    supabase = SupabaseRestClient()
    jobs = await supabase.select(
        "cron_jobs",
        {
            "user_id": f"eq.{user.id}",
            "select": "*",
            "order": "created_at.desc",
        },
    )
    return {"jobs": jobs}


@router.post("/jobs", status_code=status.HTTP_201_CREATED)
async def create_cron_job(
    request: CronJobCreateRequest,
    user: AuthenticatedUser = Depends(verify_supabase_user),
) -> dict[str, Any]:
    name = _validate_or_422(lambda: _normalize_name(request.name))
    schedule = _validate_or_422(lambda: validate_cron_schedule(request.schedule))
    task = _validate_or_422(lambda: _normalize_task(request.task))
    timezone_name = _validate_or_422(lambda: validate_timezone(request.timezone))
    next_run_at = (
        _validate_or_422(
            lambda: compute_next_run_at(schedule, timezone_name=timezone_name),
        ).isoformat()
        if request.enabled
        else None
    )

    supabase = SupabaseRestClient()
    job = await supabase.insert(
        "cron_jobs",
        {
            "user_id": user.id,
            "name": name,
            "schedule": schedule,
            "task": task,
            "payload": request.payload,
            "enabled": request.enabled,
            "timezone": timezone_name,
            "max_retries": request.max_retries,
            "timeout_seconds": request.timeout_seconds,
            "retry_delay_seconds": request.retry_delay_seconds,
            "idempotency_key": request.idempotency_key,
            "next_run_at": next_run_at,
        },
    )
    await write_audit_log(
        supabase,
        user_id=user.id,
        actor_type="worker",
        event_type="cron_job.created",
        target_table="cron_jobs",
        target_id=str(job["id"]),
        metadata={"task": task, "schedule": schedule},
    )
    return {"job": job}


@router.get("/jobs/{job_id}")
async def get_cron_job(
    job_id: str,
    user: AuthenticatedUser = Depends(verify_supabase_user),
) -> dict[str, Any]:
    supabase = SupabaseRestClient()
    job = await _get_owned_job(supabase, user_id=user.id, job_id=job_id)
    return {"job": job}


@router.patch("/jobs/{job_id}")
async def update_cron_job(
    job_id: str,
    request: CronJobUpdateRequest,
    user: AuthenticatedUser = Depends(verify_supabase_user),
) -> dict[str, Any]:
    supabase = SupabaseRestClient()
    existing = await _get_owned_job(supabase, user_id=user.id, job_id=job_id)
    updates: dict[str, Any] = {}
    fields_set = request.model_fields_set

    if "name" in fields_set:
        updates["name"] = _validate_or_422(lambda: _normalize_name(request.name))
    if "schedule" in fields_set:
        updates["schedule"] = _validate_or_422(
            lambda: validate_cron_schedule(request.schedule or ""),
        )
    if "task" in fields_set:
        updates["task"] = _validate_or_422(lambda: _normalize_task(request.task))
    if "payload" in fields_set:
        updates["payload"] = request.payload or {}
    if "enabled" in fields_set:
        updates["enabled"] = bool(request.enabled)
    if "timezone" in fields_set:
        updates["timezone"] = _validate_or_422(
            lambda: validate_timezone(request.timezone),
        )
    if request.max_retries is not None:
        updates["max_retries"] = request.max_retries
    if request.timeout_seconds is not None:
        updates["timeout_seconds"] = request.timeout_seconds
    if request.retry_delay_seconds is not None:
        updates["retry_delay_seconds"] = request.retry_delay_seconds

    if not updates:
        return {"job": existing}

    should_recompute_next_run = bool(
        {"schedule", "timezone", "enabled"} & set(updates.keys())
    )
    if should_recompute_next_run:
        effective_enabled = bool(updates.get("enabled", existing.get("enabled")))
        effective_schedule = str(updates.get("schedule", existing.get("schedule")))
        effective_timezone = str(updates.get("timezone", existing.get("timezone")))
        updates["next_run_at"] = (
            _validate_or_422(
                lambda: compute_next_run_at(
                    effective_schedule,
                    timezone_name=effective_timezone,
                ),
            ).isoformat()
            if effective_enabled
            else None
        )
        if not effective_enabled:
            updates["locked_at"] = None
            updates["locked_by"] = None

    updates["updated_at"] = _now_iso()
    job = await supabase.update_by_id("cron_jobs", job_id, updates)
    await write_audit_log(
        supabase,
        user_id=user.id,
        actor_type="worker",
        event_type="cron_job.updated",
        target_table="cron_jobs",
        target_id=job_id,
        metadata={"changed": sorted(updates.keys())},
    )
    return {
        "job": job
        or await _get_owned_job(supabase, user_id=user.id, job_id=job_id)
    }


@router.get("/jobs/{job_id}/executions")
async def list_cron_job_executions(
    job_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    user: AuthenticatedUser = Depends(verify_supabase_user),
) -> dict[str, Any]:
    supabase = SupabaseRestClient()
    await _get_owned_job(supabase, user_id=user.id, job_id=job_id)
    executions = await supabase.select(
        "cron_job_executions",
        {
            "cron_job_id": f"eq.{job_id}",
            "user_id": f"eq.{user.id}",
            "select": "*",
            "order": "created_at.desc",
            "limit": str(limit),
        },
    )
    return {"executions": executions}
