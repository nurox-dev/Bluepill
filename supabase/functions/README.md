# Supabase Edge Functions

This directory is the API gateway layer from `docs/architecture.md`.

## Functions

- `agent-chat`: validates the user JWT, rate-limits, creates `agent_runs`, saves the user message, and enqueues QStash.
- `schedule-job`: validates the user JWT, creates `scheduled_jobs`, and publishes delayed work to QStash.
- Recurring cron jobs are handled by the FastAPI worker through `/cron/jobs` and the `cron_jobs` / `cron_job_executions` tables, not by an Edge Function.
- `approve-action`: records user approval/rejection and wakes the worker when an approved run can continue.

## Shared Modules

- `_shared/auth.ts`: Supabase JWT verification.
- `_shared/permissions.ts`: rate-limit and connected-account checks.
- `_shared/qstash.ts`: QStash publishing.
- `_shared/audit.ts`: audit log writes.
- `_shared/cors.ts`: CORS and JSON helpers.
- `_shared/supabase.ts`: Supabase clients.
- `_shared/env.ts`: server-only environment variables.

Edge Functions should stay fast. Long-running agent work belongs in the FastAPI worker.
