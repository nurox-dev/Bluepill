import json
import secrets
from datetime import UTC, datetime
from typing import Any

import httpx
from mcp.server.auth.settings import AuthSettings
from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse, RedirectResponse

from app.config import get_settings
from app.mcp.auth import SupabaseTokenVerifier, require_user_id
from app.services.supabase import SupabaseRestClient

settings = get_settings()

mcp = FastMCP(
    "BluePill MCP",
    instructions="Personal life dashboard — tasks, goals, habits, check-ins, progress, and AI agent. "
    "Connect any MCP-compatible AI platform (Claude, Cursor, OpenAI) to your BluePill data.",
    token_verifier=SupabaseTokenVerifier(),
    auth=AuthSettings(
        issuer_url=f"{settings.supabase_url}/auth/v1",
        resource_server_url=f"{settings.supabase_url}/rest/v1",
        required_scopes=["user"],
    ),
)

_db = SupabaseRestClient()


def _user_filter(
    user_id: str, extra: dict[str, str] | None = None
) -> dict[str, str]:
    f: dict[str, str] = {"user_id": f"eq.{user_id}", "select": "*"}
    if extra:
        f.update(extra)
    return f


async def _call_worker(path: str, body: dict[str, Any]) -> dict[str, Any]:
    s = get_settings()
    if not s.mcp_worker_base_url or not s.worker_shared_secret:
        raise RuntimeError(
            "mcp_worker_base_url and worker_shared_secret must be configured"
        )
    async with httpx.AsyncClient(timeout=120) as client:
        r = await client.post(
            f"{s.mcp_worker_base_url.rstrip('/')}{path}",
            headers={
                "Authorization": f"Bearer {s.worker_shared_secret}",
                "Content-Type": "application/json",
            },
            json=body,
        )
        r.raise_for_status()
        return r.json()


# ---------------------------------------------------------------------------
# Rate limiter
# ---------------------------------------------------------------------------

async def _check_rate_limit(
    user_id: str, endpoint: str, limit: int = 50
) -> bool:
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    try:
        rows = await _db.select(
            "rate_limit_events",
            {
                "user_id": f"eq.{user_id}",
                "endpoint": f"eq.{endpoint}",
                "select": "id",
                "created_at": f"gte.{today}",
                "limit": "1",
            },
        )
        return len(rows) < limit
    except Exception:
        return True


async def _record_rate_limit(
    user_id: str, endpoint: str, action: str, allowed: bool
) -> None:
    try:
        await _db.insert(
            "rate_limit_events",
            {
                "user_id": user_id,
                "endpoint": endpoint,
                "action": action,
                "allowed": allowed,
            },
        )
    except Exception:
        pass


# ---------------------------------------------------------------------------
# DISCOVERY & HEALTH (no auth required)
# ---------------------------------------------------------------------------

@mcp.custom_route("/health", methods=["GET"], include_in_schema=True)
async def health_route(request: Request) -> JSONResponse:
    return JSONResponse({"status": "ok", "service": "bluepill-mcp"})


@mcp.custom_route("/.well-known/mcp.json", methods=["GET"], include_in_schema=True)
async def mcp_discovery(request: Request) -> JSONResponse:
    base = settings.mcp_public_url
    return JSONResponse(
        {
            "name": "BluePill MCP",
            "description": "Personal life dashboard — tasks, goals, habits, check-ins, and AI agent",
            "version": "1.0.0",
            "website": "https://project-bluepill.web.app",
            "capabilities": {
                "resources": {"subscribe": False, "listChanged": False},
                "tools": {"listChanged": False},
                "prompts": {"listChanged": False},
                "logging": {},
            },
            "authentication": {
                "type": "oauth2",
                "authorizationUrl": f"{base}/oauth/authorize",
                "tokenUrl": f"{base}/oauth/token",
                "scopes": ["user"],
                "pkce": True,
            },
            "tools": [
                {"name": "list_tasks", "description": "List all tasks"},
                {"name": "create_task", "description": "Create a new task"},
                {"name": "list_goals", "description": "List all goals"},
                {"name": "list_habits", "description": "List all habits"},
                {"name": "create_checkin", "description": "Create a daily check-in"},
                {"name": "search_memory", "description": "Search AI memory"},
                {"name": "ask_agent", "description": "Ask the AI agent a question"},
                {"name": "schedule_job", "description": "Schedule a job for later execution"},
                {"name": "get_task_status", "description": "Get the status of an agent run or scheduled job"},
                {"name": "get_audit_log", "description": "Read recent audit log entries"},
            ],
            "resources": [
                {"uri": "bluepill://profile", "description": "User profile"},
                {"uri": "bluepill://tasks", "description": "All tasks"},
                {"uri": "bluepill://tasks/today", "description": "Today's tasks"},
                {"uri": "bluepill://goals", "description": "All goals"},
                {"uri": "bluepill://habits", "description": "All habits"},
                {"uri": "bluepill://checkins", "description": "Recent check-ins"},
                {"uri": "bluepill://progress", "description": "Recent progress logs"},
                {"uri": "bluepill://conversations", "description": "Agent conversations"},
            ],
            "prompts": [
                {"name": "extract_checkin_progress", "description": "Extract progress from a check-in answer"},
                {"name": "weekly_review", "description": "Generate a weekly review"},
            ],
        }
    )


# ---------------------------------------------------------------------------
# OAuth2 stubs (delegates to Supabase Auth)
# ---------------------------------------------------------------------------

@mcp.custom_route("/oauth/authorize", methods=["GET"], include_in_schema=True)
async def oauth_authorize(request: Request) -> RedirectResponse:
    redirect_uri = request.query_params.get("redirect_uri", "")
    state = request.query_params.get("state", secrets.token_urlsafe(32))
    code_challenge = request.query_params.get("code_challenge", "")
    supabase_authorize_url = (
        f"{settings.supabase_url}/auth/v1/authorize"
        f"?provider=google"
        f"&redirect_to={settings.mcp_public_url}/oauth/callback"
        f"&state={state}"
    )
    return RedirectResponse(url=supabase_authorize_url)


@mcp.custom_route("/oauth/callback", methods=["GET"], include_in_schema=True)
async def oauth_callback(request: Request) -> JSONResponse:
    code = request.query_params.get("code", "")
    state = request.query_params.get("state", "")
    if not code:
        return JSONResponse({"error": "Missing authorization code"}, status_code=400)
    return JSONResponse(
        {
            "access_token": code,
            "token_type": "bearer",
            "state": state,
            "scope": "user",
        }
    )


@mcp.custom_route("/oauth/token", methods=["POST"], include_in_schema=True)
async def oauth_token(request: Request) -> JSONResponse:
    body = await request.json()
    grant_type = body.get("grant_type", "")
    if grant_type == "authorization_code":
        code = body.get("code", "")
        return JSONResponse(
            {
                "access_token": code,
                "token_type": "bearer",
                "scope": "user",
            }
        )
    return JSONResponse({"error": "unsupported_grant_type"}, status_code=400)


# ---------------------------------------------------------------------------
# RESOURCES
# ---------------------------------------------------------------------------

@mcp.resource("bluepill://profile")
async def get_profile() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "users_profile", _user_filter(user_id, {"limit": "1"})
    )
    return json.dumps(rows[0] if rows else None, indent=2, default=str)


@mcp.resource("bluepill://tasks")
async def get_tasks() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "tasks", _user_filter(user_id, {"order": "created_at.desc", "limit": "50"})
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.resource("bluepill://tasks/today")
async def get_tasks_today() -> str:
    user_id = require_user_id()
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    rows = await _db.select(
        "tasks",
        {
            "user_id": f"eq.{user_id}",
            "select": "*",
            "due_date": f"lte.{today}",
            "status": "neq.completed",
            "order": "priority.desc,created_at.asc",
            "limit": "50",
        },
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.resource("bluepill://goals")
async def get_goals() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "goals", _user_filter(user_id, {"order": "created_at.desc"})
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.resource("bluepill://habits")
async def get_habits() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "habits", _user_filter(user_id, {"order": "created_at.desc"})
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.resource("bluepill://checkins")
async def get_checkins() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "checkins",
        _user_filter(user_id, {"order": "created_at.desc", "limit": "20"}),
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.resource("bluepill://progress")
async def get_progress() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "progress_logs",
        _user_filter(user_id, {"order": "date.desc", "limit": "30"}),
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.resource("bluepill://conversations")
async def get_conversations() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "agent_conversations",
        _user_filter(user_id, {"order": "updated_at.desc", "limit": "20"}),
    )
    return json.dumps(rows, indent=2, default=str)


# ---------------------------------------------------------------------------
# TOOLS
# ---------------------------------------------------------------------------

@mcp.tool(
    description="List all tasks for the authenticated user, with optional status filter"
)
async def list_tasks(status: str | None = None) -> str:
    user_id = require_user_id()
    params = _user_filter(user_id, {"order": "created_at.desc", "limit": "50"})
    if status:
        params["status"] = f"eq.{status}"
    rows = await _db.select("tasks", params)
    return json.dumps(rows, indent=2, default=str)


@mcp.tool(description="Create a new task")
async def create_task(
    title: str,
    description: str | None = None,
    priority: str | None = None,
    category: str | None = None,
    due_date: str | None = None,
    estimated_minutes: int | None = None,
) -> str:
    user_id = require_user_id()
    payload: dict[str, Any] = {"user_id": user_id, "title": title}
    if description:
        payload["description"] = description
    if priority:
        payload["priority"] = priority
    if category:
        payload["category"] = category
    if due_date:
        payload["due_date"] = due_date
    if estimated_minutes is not None:
        payload["estimated_minutes"] = estimated_minutes
    row = await _db.insert("tasks", payload)
    return json.dumps(row, indent=2, default=str)


@mcp.tool(description="Update an existing task")
async def update_task(
    task_id: str,
    title: str | None = None,
    description: str | None = None,
    priority: str | None = None,
    category: str | None = None,
    status: str | None = None,
    due_date: str | None = None,
) -> str:
    user_id = require_user_id()
    payload: dict[str, Any] = {}
    if title is not None:
        payload["title"] = title
    if description is not None:
        payload["description"] = description
    if priority is not None:
        payload["priority"] = priority
    if category is not None:
        payload["category"] = category
    if status is not None:
        payload["status"] = status
    if due_date is not None:
        payload["due_date"] = due_date
    row = await _db.select(
        "tasks",
        {"id": f"eq.{task_id}", "user_id": f"eq.{user_id}", "select": "*", "limit": "1"},
    )
    if not row:
        return json.dumps({"error": "Task not found"}, indent=2)
    await _db.update_by_id("tasks", task_id, payload)
    rows = await _db.select(
        "tasks",
        {"id": f"eq.{task_id}", "user_id": f"eq.{user_id}", "select": "*", "limit": "1"},
    )
    return json.dumps(rows[0] if rows else {}, indent=2, default=str)


@mcp.tool(description="Delete a task")
async def delete_task(task_id: str) -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "tasks",
        {"id": f"eq.{task_id}", "user_id": f"eq.{user_id}", "select": "id", "limit": "1"},
    )
    if not rows:
        return json.dumps({"error": "Task not found"}, indent=2)
    async with httpx.AsyncClient(timeout=30) as client:
        s = get_settings()
        r = await client.delete(
            f"{s.supabase_url}/rest/v1/tasks",
            headers={
                "apikey": s.supabase_service_role_key,
                "Authorization": f"Bearer {s.supabase_service_role_key}",
            },
            params={"id": f"eq.{task_id}", "user_id": f"eq.{user_id}"},
        )
        r.raise_for_status()
    return json.dumps({"deleted": task_id})


@mcp.tool(description="List all goals for the authenticated user")
async def list_goals() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "goals", _user_filter(user_id, {"order": "created_at.desc"})
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.tool(description="Create a new goal")
async def create_goal(
    title: str,
    goal_type: str | None = None,
    description: str | None = None,
    deadline: str | None = None,
) -> str:
    user_id = require_user_id()
    payload: dict[str, Any] = {"user_id": user_id, "title": title}
    if goal_type:
        payload["goal_type"] = goal_type
    if description:
        payload["description"] = description
    if deadline:
        payload["deadline"] = deadline
    row = await _db.insert("goals", payload)
    return json.dumps(row, indent=2, default=str)


@mcp.tool(description="Update an existing goal")
async def update_goal(
    goal_id: str,
    title: str | None = None,
    status: str | None = None,
    progress_percent: float | None = None,
) -> str:
    user_id = require_user_id()
    payload: dict[str, Any] = {}
    if title is not None:
        payload["title"] = title
    if status is not None:
        payload["status"] = status
    if progress_percent is not None:
        payload["progress_percent"] = progress_percent
    rows = await _db.select(
        "goals",
        {"id": f"eq.{goal_id}", "user_id": f"eq.{user_id}", "select": "*", "limit": "1"},
    )
    if not rows:
        return json.dumps({"error": "Goal not found"}, indent=2)
    await _db.update_by_id("goals", goal_id, payload)
    rows = await _db.select(
        "goals",
        {"id": f"eq.{goal_id}", "user_id": f"eq.{user_id}", "select": "*", "limit": "1"},
    )
    return json.dumps(rows[0] if rows else {}, indent=2, default=str)


@mcp.tool(description="List all habits for the authenticated user")
async def list_habits() -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "habits", _user_filter(user_id, {"order": "created_at.desc"})
    )
    return json.dumps(rows, indent=2, default=str)


@mcp.tool(description="Create a new habit")
async def create_habit(
    title: str,
    frequency: str | None = None,
    category: str | None = None,
    target: int | None = None,
) -> str:
    user_id = require_user_id()
    payload: dict[str, Any] = {"user_id": user_id, "title": title}
    if frequency:
        payload["frequency"] = frequency
    if category:
        payload["category"] = category
    if target is not None:
        payload["target"] = target
    row = await _db.insert("habits", payload)
    return json.dumps(row, indent=2, default=str)


@mcp.tool(description="Log a habit completion for today")
async def log_habit(
    habit_id: str, status: str, notes: str | None = None
) -> str:
    user_id = require_user_id()
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    payload: dict[str, Any] = {
        "habit_id": habit_id,
        "user_id": user_id,
        "date": today,
        "status": status,
    }
    if notes:
        payload["notes"] = notes
    row = await _db.insert("habit_logs", payload)
    return json.dumps(row, indent=2, default=str)


@mcp.tool(description="Create a daily check-in entry")
async def create_checkin(
    type: str, user_answer: str, question: str | None = None
) -> str:
    user_id = require_user_id()
    payload: dict[str, Any] = {
        "user_id": user_id,
        "type": type,
        "user_answer": user_answer,
    }
    if question:
        payload["question"] = question
    row = await _db.insert("checkins", payload)
    return json.dumps(row, indent=2, default=str)


@mcp.tool(description="Search the user's AI memory for relevant context")
async def search_memory(query: str, limit: int = 5) -> str:
    user_id = require_user_id()
    try:
        results = await _db.rpc(
            "match_agent_memory",
            {
                "p_user_id": user_id,
                "p_query": query,
                "p_match_count": limit,
            },
        )
    except Exception:
        results = []
    return json.dumps(results, indent=2, default=str)


# ---------------------------------------------------------------------------
# TOOLS — ask_agent, schedule_job, get_task_status, get_audit_log
# ---------------------------------------------------------------------------

@mcp.tool(
    name="ask_agent",
    description="Send a message to the AI agent and get a response. "
    "Use this for questions, task management, planning, or any AI assistance.",
)
async def ask_agent(message: str, conversation_id: str | None = None) -> str:
    user_id = require_user_id()
    if not await _check_rate_limit(user_id, "agent-chat", settings.agent_daily_run_limit):
        return json.dumps(
            {"error": "Daily rate limit exceeded. Try again tomorrow."}
        )
    await _record_rate_limit(user_id, "agent-chat", "ask_agent", True)
    body: dict[str, Any] = {"message": message}
    if conversation_id:
        body["conversation_id"] = conversation_id
    try:
        result = await _call_worker("/agent/chat", body)
        return json.dumps(result, indent=2, default=str)
    except Exception as e:
        return json.dumps(
            {
                "error": "Agent worker unavailable",
                "detail": str(e),
                "hint": "Configure MCP_WORKER_BASE_URL and WORKER_SHARED_SECRET on the worker.",
            }
        )


@mcp.tool(
    name="schedule_job",
    description="Schedule a job to run at a future time. "
    "Jobs are processed by the worker. Use this for reminders, recurring tasks, or delayed actions.",
)
async def schedule_job(
    job_type: str,
    scheduled_for: str,
    payload: str | None = None,
) -> str:
    user_id = require_user_id()
    job: dict[str, Any] = {
        "user_id": user_id,
        "job_type": job_type,
        "status": "scheduled",
        "queue_provider": "qstash",
        "scheduled_for": scheduled_for,
        "payload": json.loads(payload) if payload else {},
    }
    row = await _db.insert("scheduled_jobs", job)
    return json.dumps(
        {
            "scheduled_job_id": row.get("id"),
            "status": "scheduled",
            "scheduled_for": scheduled_for,
        },
        indent=2,
        default=str,
    )


@mcp.tool(
    name="get_task_status",
    description="Get the current status of an agent run or scheduled job. "
    "Use this to check whether an ask_agent or schedule_job call completed.",
)
async def get_task_status(run_id: str) -> str:
    user_id = require_user_id()
    agent_run = await _db.select_by_id("agent_runs", run_id)
    if agent_run:
        return json.dumps(agent_run, indent=2, default=str)
    scheduled = await _db.select_by_id("scheduled_jobs", run_id)
    if scheduled:
        return json.dumps(scheduled, indent=2, default=str)
    return json.dumps({"error": "Run not found"}, indent=2)


@mcp.tool(
    name="get_audit_log",
    description="Read recent audit log entries for the authenticated user. "
    "Audit logs record all significant actions taken by the agent.",
)
async def get_audit_log(limit: int = 20) -> str:
    user_id = require_user_id()
    rows = await _db.select(
        "audit_logs",
        _user_filter(user_id, {"order": "created_at.desc", "limit": str(limit)}),
    )
    return json.dumps(rows, indent=2, default=str)


# ---------------------------------------------------------------------------
# PROMPTS
# ---------------------------------------------------------------------------

@mcp.prompt(
    name="extract_checkin_progress",
    description="Extract structured progress data from a natural language check-in answer",
)
def extract_checkin_progress_prompt() -> str:
    return """You are helping extract structured data from a user's daily check-in answer.

Given the user's free-form answer, extract:
- completed_tasks: list of task titles they completed
- missed_tasks: list of task titles they missed or didn't do
- habits_completed: list of habit names they completed
- focus_score: number 1-10
- mood: their mood (happy, neutral, tired, stressed, etc.)
- blockers: any obstacles they mentioned

Return the result as JSON."""


@mcp.prompt(
    name="weekly_review",
    description="Generate a concise weekly review based on the user's progress data",
)
def weekly_review_prompt() -> str:
    return """You are helping the user review their past week.

Given their tasks, habits, check-ins, and progress logs for the last 7 days, generate:
1. What worked well
2. What didn't work
3. One change they could make next week

Keep it concise and actionable."""


# ---------------------------------------------------------------------------
# SSE app for mounting into the worker's FastAPI
# ---------------------------------------------------------------------------

def get_mcp_sse_app():
    return mcp.sse_app()
