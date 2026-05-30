# BluePill FastAPI Worker

This worker is the execution engine from `docs/architecture.md`.

It receives QStash webhook deliveries, loads durable state from Supabase, runs the OpenAI Agents SDK, calls approved tools, writes audit logs, and updates Realtime-visible tables.

## Local Setup

```bash
cd worker
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Use `server.env.example` as the source for required environment variables.

## Endpoints

- `GET /healthz`: health check.
- `POST /cron/jobs`: create a recurring cron job for the authenticated user.
- `GET /cron/jobs`: list the authenticated user's cron jobs.
- `GET /cron/jobs/{job_id}`: read one cron job definition.
- `PATCH /cron/jobs/{job_id}`: update name, schedule, task, payload, enabled state, retries, or timeout.
- `GET /cron/jobs/{job_id}/executions`: list execution logs/status for a cron job.
- `POST /jobs/agent-run`: QStash delivery for immediate agent runs.
- `POST /jobs/scheduled-job`: QStash delivery for scheduled jobs.

## Cron Jobs

Recurring cron jobs are stored in `cron_jobs`; each run is written to
`cron_job_executions`. The worker starts a lightweight scheduler on boot when
`CRON_SCHEDULER_ENABLED=true`, polls for due jobs, claims rows through
`claim_due_cron_jobs`, then executes only whitelisted task names.

Job definition fields:

- `name`: human-readable label.
- `schedule`: cron expression, such as `0 9 * * *`.
- `task`: whitelisted action. Supported values: `agent_prompt`, `noop`.
- `payload`: task-specific JSON. `agent_prompt` expects `message` or `prompt`.
- `enabled`: disabled jobs are not claimed.
- `last_run_at` / `next_run_at`: maintained by the worker.
- `last_status` / `last_error`: summary of the latest execution.

Execution safety:

- Jobs are claimed with row locks and a stale-lock TTL.
- Each execution records status, attempts, logs, duration, result, and error.
- Per-job `max_retries`, `retry_delay_seconds`, and `timeout_seconds` control retries and timeout handling.
- Tasks are selected from a Python registry; arbitrary shell commands or URLs are not executed.

## Module Map

- `app/main.py`: FastAPI entrypoint.
- `app/security/`: QStash/shared-secret verification.
- `app/jobs/`: job execution handlers and recurring cron scheduler.
- `app/agents/`: OpenAI Agents SDK orchestration.
- `app/services/`: Supabase, context, and audit helpers.
- `app/tools/`: active agent helper tools. Current code keeps memory search only; external write tools should be added when they are wired into the agent runtime.
