import asyncio
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.agent_chat import router as agent_chat_router
from app.api.cron_jobs import router as cron_jobs_router
from app.config import get_settings
from app.jobs.agent_runs import AgentRunDelivery, process_agent_run
from app.jobs.cron_scheduler import CronScheduler
from app.jobs.scheduled_jobs import ScheduledJobDelivery, process_scheduled_job
from app.mcp.gateway import get_mcp_sse_app
from app.security.worker_auth import verify_worker_request

settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI):
    scheduler_task: asyncio.Task[None] | None = None
    if settings.cron_scheduler_enabled:
        scheduler = CronScheduler(
            interval_seconds=settings.cron_scheduler_interval_seconds,
            batch_size=settings.cron_scheduler_batch_size,
            lock_ttl_seconds=settings.cron_scheduler_lock_ttl_seconds,
        )
        scheduler_task = asyncio.create_task(
            scheduler.run_forever(),
            name="cron-scheduler",
        )

    try:
        yield
    finally:
        if scheduler_task:
            scheduler_task.cancel()
            try:
                await scheduler_task
            except asyncio.CancelledError:
                pass


app = FastAPI(title="BluePill Worker", lifespan=lifespan)
allow_origins = [
    origin.strip()
    for origin in settings.cors_allow_origins.split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins or ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(agent_chat_router)
app.include_router(cron_jobs_router)

if settings.mcp_enabled:
    app.mount("/mcp", get_mcp_sse_app(), name="mcp")


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/jobs/agent-run", dependencies=[Depends(verify_worker_request)])
async def agent_run_job(payload: AgentRunDelivery) -> dict[str, str]:
    await process_agent_run(payload)
    return {"status": "accepted"}


@app.post("/jobs/scheduled-job", dependencies=[Depends(verify_worker_request)])
async def scheduled_job(payload: ScheduledJobDelivery) -> dict[str, str]:
    await process_scheduled_job(payload)
    return {"status": "accepted"}
