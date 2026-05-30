import asyncio
import logging
import os
import socket
from datetime import UTC, datetime
from time import monotonic
from typing import Any
from uuid import uuid4
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from croniter import croniter

from app.jobs.cron_tasks import execute_cron_task
from app.services.audit import write_audit_log
from app.services.supabase import SupabaseRestClient

logger = logging.getLogger(__name__)


class CronExecutionFailure(Exception):
    def __init__(
        self,
        *,
        status: str,
        error: str,
        attempts: int,
        logs: list[dict[str, Any]],
    ) -> None:
        super().__init__(error)
        self.status = status
        self.error = error
        self.attempts = attempts
        self.logs = logs


def _now() -> datetime:
    return datetime.now(UTC)


def _now_iso() -> str:
    return _now().isoformat()


def _parse_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _bounded_int(
    value: Any,
    *,
    default: int,
    minimum: int,
    maximum: int,
) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(minimum, min(maximum, parsed))


def validate_cron_schedule(schedule: str) -> str:
    normalized = " ".join(schedule.strip().split())
    if not normalized:
        raise ValueError("schedule is required.")
    if not croniter.is_valid(normalized):
        raise ValueError("schedule must be a valid cron expression.")
    return normalized


def validate_timezone(timezone_name: str | None) -> str:
    normalized = (timezone_name or "UTC").strip() or "UTC"
    try:
        ZoneInfo(normalized)
    except ZoneInfoNotFoundError as error:
        raise ValueError(f"Unsupported timezone: {normalized}") from error
    return normalized


def compute_next_run_at(
    schedule: str,
    *,
    timezone_name: str = "UTC",
    after: datetime | None = None,
) -> datetime:
    normalized_schedule = validate_cron_schedule(schedule)
    normalized_timezone = validate_timezone(timezone_name)
    zone = ZoneInfo(normalized_timezone)
    base = after or _now()
    base = base.replace(tzinfo=UTC) if base.tzinfo is None else base.astimezone(UTC)
    base_local = base.astimezone(zone)
    next_local = croniter(normalized_schedule, base_local).get_next(datetime)
    if next_local.tzinfo is None:
        next_local = next_local.replace(tzinfo=zone)
    return next_local.astimezone(UTC)


class CronScheduler:
    def __init__(
        self,
        *,
        interval_seconds: int,
        batch_size: int,
        lock_ttl_seconds: int,
        worker_id: str | None = None,
    ) -> None:
        self.interval_seconds = max(5, interval_seconds)
        self.batch_size = max(1, batch_size)
        self.lock_ttl_seconds = max(30, lock_ttl_seconds)
        self.worker_id = worker_id or (
            f"{socket.gethostname()}:{os.getpid()}:{uuid4().hex[:8]}"
        )

    async def run_forever(self) -> None:
        logger.info("Cron scheduler started as %s", self.worker_id)
        try:
            while True:
                try:
                    await self.run_once()
                except asyncio.CancelledError:
                    raise
                except Exception:
                    logger.exception("Cron scheduler tick failed")
                await asyncio.sleep(self.interval_seconds)
        finally:
            logger.info("Cron scheduler stopped")

    async def run_once(self) -> int:
        supabase = SupabaseRestClient()
        claimed = await supabase.rpc(
            "claim_due_cron_jobs",
            {
                "p_limit": self.batch_size,
                "p_worker_id": self.worker_id,
                "p_now": _now_iso(),
                "p_lock_ttl_seconds": self.lock_ttl_seconds,
            },
        )
        if not isinstance(claimed, list) or not claimed:
            return 0

        results = await asyncio.gather(
            *(self.process_job(job) for job in claimed),
            return_exceptions=True,
        )
        for result in results:
            if isinstance(result, Exception):
                logger.error(
                    "Cron job processing failed: %s",
                    result,
                    exc_info=(type(result), result, result.__traceback__),
                )
        return len(claimed)

    async def process_job(self, job: dict[str, Any]) -> None:
        supabase = SupabaseRestClient()
        job_id = str(job["id"])
        user_id = str(job["user_id"])
        started_at = _now()
        scheduled_for = _parse_datetime(job.get("next_run_at")) or started_at
        execution_id: str | None = None
        status = "failed"
        error: str | None = None
        attempts = 0
        logs: list[dict[str, Any]] = []
        result: dict[str, Any] = {}

        try:
            execution = await supabase.insert(
                "cron_job_executions",
                {
                    "cron_job_id": job_id,
                    "user_id": user_id,
                    "scheduled_for": scheduled_for.isoformat(),
                    "task": job.get("task"),
                    "payload": job.get("payload") or {},
                    "status": "running",
                    "attempts": 0,
                    "max_retries": _bounded_int(
                        job.get("max_retries"),
                        default=0,
                        minimum=0,
                        maximum=10,
                    ),
                    "timeout_seconds": _bounded_int(
                        job.get("timeout_seconds"),
                        default=300,
                        minimum=1,
                        maximum=3600,
                    ),
                    "started_at": started_at.isoformat(),
                },
            )
            execution_id = str(execution["id"])
            await write_audit_log(
                supabase,
                user_id=user_id,
                actor_type="worker",
                event_type="cron_job.started",
                target_table="cron_jobs",
                target_id=job_id,
                metadata={"cron_execution_id": execution_id, "task": job.get("task")},
            )

            result, attempts, logs = await self._run_with_retries(
                supabase,
                job=job,
                execution_id=execution_id,
            )
            status = "succeeded"
        except CronExecutionFailure as failure:
            status = failure.status
            error = failure.error
            attempts = failure.attempts
            logs = failure.logs
        except Exception as unexpected:
            status = "failed"
            error = str(unexpected)
            logs.append(
                {
                    "level": "error",
                    "message": error,
                    "timestamp": _now_iso(),
                }
            )
        finally:
            completed_at = _now()
            duration_ms = int((completed_at - started_at).total_seconds() * 1000)
            await self._finish_execution(
                supabase,
                job=job,
                execution_id=execution_id,
                status=status,
                result=result,
                error=error,
                attempts=attempts,
                logs=logs,
                completed_at=completed_at,
                duration_ms=duration_ms,
            )

    async def _run_with_retries(
        self,
        supabase: SupabaseRestClient,
        *,
        job: dict[str, Any],
        execution_id: str,
    ) -> tuple[dict[str, Any], int, list[dict[str, Any]]]:
        max_retries = _bounded_int(
            job.get("max_retries"),
            default=0,
            minimum=0,
            maximum=10,
        )
        timeout_seconds = _bounded_int(
            job.get("timeout_seconds"),
            default=300,
            minimum=1,
            maximum=3600,
        )
        retry_delay_seconds = _bounded_int(
            job.get("retry_delay_seconds"),
            default=30,
            minimum=0,
            maximum=3600,
        )
        logs: list[dict[str, Any]] = []
        attempts = 0
        last_error = ""
        last_status = "failed"

        for attempt_index in range(max_retries + 1):
            attempts = attempt_index + 1
            attempt_started = monotonic()
            logs.append(
                {
                    "level": "info",
                    "message": f"Attempt {attempts} started.",
                    "timestamp": _now_iso(),
                }
            )
            await supabase.update_by_id(
                "cron_job_executions",
                execution_id,
                {
                    "attempts": attempts,
                    "logs": logs,
                    "updated_at": _now_iso(),
                },
            )

            try:
                result = await asyncio.wait_for(
                    execute_cron_task(
                        supabase,
                        job=job,
                        execution_id=execution_id,
                    ),
                    timeout=timeout_seconds,
                )
                elapsed_ms = int((monotonic() - attempt_started) * 1000)
                logs.append(
                    {
                        "level": "info",
                        "message": f"Attempt {attempts} succeeded.",
                        "timestamp": _now_iso(),
                        "duration_ms": elapsed_ms,
                    }
                )
                return result, attempts, logs
            except asyncio.TimeoutError:
                last_status = "timed_out"
                last_error = f"Task timed out after {timeout_seconds} seconds."
            except Exception as error:
                last_status = "failed"
                last_error = str(error)

            logs.append(
                {
                    "level": "error",
                    "message": last_error,
                    "timestamp": _now_iso(),
                    "attempt": attempts,
                }
            )
            await supabase.update_by_id(
                "cron_job_executions",
                execution_id,
                {
                    "attempts": attempts,
                    "logs": logs,
                    "updated_at": _now_iso(),
                },
            )

            if attempt_index < max_retries:
                logs.append(
                    {
                        "level": "info",
                        "message": f"Retrying in {retry_delay_seconds} seconds.",
                        "timestamp": _now_iso(),
                    }
                )
                await supabase.update_by_id(
                    "cron_job_executions",
                    execution_id,
                    {"logs": logs, "updated_at": _now_iso()},
                )
                if retry_delay_seconds > 0:
                    await asyncio.sleep(retry_delay_seconds)

        raise CronExecutionFailure(
            status=last_status,
            error=last_error,
            attempts=attempts,
            logs=logs,
        )

    async def _finish_execution(
        self,
        supabase: SupabaseRestClient,
        *,
        job: dict[str, Any],
        execution_id: str | None,
        status: str,
        result: dict[str, Any],
        error: str | None,
        attempts: int,
        logs: list[dict[str, Any]],
        completed_at: datetime,
        duration_ms: int,
    ) -> None:
        job_id = str(job["id"])
        user_id = str(job["user_id"])

        if execution_id:
            await supabase.update_by_id(
                "cron_job_executions",
                execution_id,
                {
                    "status": status,
                    "attempts": attempts,
                    "result": result,
                    "error": error,
                    "logs": logs,
                    "completed_at": completed_at.isoformat(),
                    "duration_ms": duration_ms,
                    "updated_at": completed_at.isoformat(),
                },
            )

        fresh_job = await supabase.select_by_id("cron_jobs", job_id)
        enabled = bool((fresh_job or job).get("enabled"))
        next_run_at = None
        if enabled:
            try:
                next_run_at = compute_next_run_at(
                    str((fresh_job or job).get("schedule") or job["schedule"]),
                    timezone_name=str((fresh_job or job).get("timezone") or "UTC"),
                    after=completed_at,
                ).isoformat()
            except ValueError as schedule_error:
                status = "failed"
                error = f"{error}\n{schedule_error}" if error else str(schedule_error)
                logs.append(
                    {
                        "level": "error",
                        "message": str(schedule_error),
                        "timestamp": _now_iso(),
                    }
                )
                if execution_id:
                    await supabase.update_by_id(
                        "cron_job_executions",
                        execution_id,
                        {
                            "status": status,
                            "error": error,
                            "logs": logs,
                            "updated_at": _now_iso(),
                        },
                    )

        await supabase.update_by_id(
            "cron_jobs",
            job_id,
            {
                "last_run_at": completed_at.isoformat(),
                "next_run_at": next_run_at,
                "last_status": status,
                "last_error": error,
                "locked_at": None,
                "locked_by": None,
                "updated_at": completed_at.isoformat(),
            },
        )

        await write_audit_log(
            supabase,
            user_id=user_id,
            actor_type="worker",
            event_type=f"cron_job.{status}",
            target_table="cron_jobs",
            target_id=job_id,
            metadata={
                "cron_execution_id": execution_id,
                "task": job.get("task"),
                "attempts": attempts,
                "error": error,
            },
        )
