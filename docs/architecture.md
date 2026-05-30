# Project BluePill Production Architecture

This is the final production architecture for BluePill. It defines where user experience, identity, API security, queueing, agent execution, tools, auditability, and realtime updates live.

## Final Flow

### Primary (QStash-mediated) Flow

```text
Flutter App
  -> Supabase Edge Functions (agent-chat)
  -> Permission + Rate Limit Check
  -> Create agent_run
  -> Upstash QStash
  -> FastAPI Worker
  -> OpenAI Agents SDK
  -> Tool Layer
  -> Audit Logs + Realtime Updates
  -> Flutter UI
```

### Direct FastAPI Flow (development/testing)

```text
Flutter App
  -> FastAPI Worker (/agent/chat)
  -> Permission + Rate Limit Check
  -> Create agent_run
  -> OpenAI Agents SDK
  -> Tool Layer
  -> Audit Logs + Realtime Updates
  -> Flutter UI
```

### Scheduled Job Flow

```text
Supabase Edge Functions (schedule-job)
  -> Create scheduled_job
  -> Upstash QStash (delayed)
  -> FastAPI Worker (/jobs/scheduled-job)
  -> Execute scheduled job
  -> Create agent_run (optional)
  -> OpenAI Agents SDK
  -> Tool Layer
  -> Audit Logs + Realtime Updates
```

## Simple Summary

- Flutter = user experience
- Supabase Auth = identity
- Edge Functions = secure entry point
- Permissions and rate limits = safety and control
- `agent_run` / `scheduled_job` = task tracking
- QStash = queue and scheduling
- FastAPI Worker = execution engine
- OpenAI Agents SDK = agent brain and orchestrator
- Tool Layer = real-world actions
- Audit + Realtime = trust and visibility
- Flutter UI = final user feedback

## Flutter App

Flutter is the user interface. Users chat with the agent, manage tasks, approve actions, view calendar suggestions, receive realtime updates, and configure settings.

The production web build is hosted on Firebase Hosting at `https://project-bluepill.web.app`. FlutterFire is configured for the web target through `firebase_core` and `flutter/lib/firebase_options.dart`. The native Linux build currently skips Firebase initialization because the installed official `firebase_core` package does not provide a Linux plugin in this workspace.

Flutter responsibilities:

- Render chat, tasks, calendar suggestions, settings, approvals, and progress states.
- Hold the Supabase Auth session and send the user JWT with backend requests.
- Upload user-selected files to Supabase Storage.
- Subscribe to Supabase Realtime channels for agent progress.
- Display final responses, approval prompts, notifications, and history.

Flutter must not:

- Contain secret API keys.
- Run heavy agent logic.
- Call OpenAI, Google, Firebase admin APIs, or service-role Supabase APIs directly in production.
- Make final permission decisions for sensitive actions.

## Supabase Auth

Supabase Auth handles login and identity. It verifies who the user is through email, Google login, Apple login, or another configured provider.

Every request from Flutter should carry the user's Supabase JWT. Edge Functions use that JWT to identify the user, enforce ownership, and decide what the user can access.

Identity rules:

- `auth.uid()` is the source of truth for user ownership.
- User-facing database rows should include `user_id`.
- Row Level Security should protect user data.
- Server-side code should only use service-role credentials inside Edge Functions or the FastAPI worker.

## Supabase Edge Functions

Supabase Edge Functions are the API gateway layer for the QStash-mediated flow. They receive requests from Flutter, verify the Supabase user token, perform lightweight checks, create database records, and send work to QStash.

The `/agent/chat` endpoint in the FastAPI worker also provides the same functionality for direct worker calls (development/testing).

Edge Function responsibilities:

- Verify the Supabase JWT.
- Normalize and validate request payloads.
- Perform permission and rate-limit checks.
- Create `agent_runs` for immediate work.
- Create `scheduled_jobs` for future or recurring work.
- Enqueue QStash messages.
- Return quickly with a tracking id and initial status.
- Write audit logs for important decisions.

Edge Functions should not:

- Run long agent tasks.
- Perform slow multi-step workflows.
- Hold OpenAI agent loops open while Flutter waits.
- Execute sensitive tool actions without permission checks.

## Permission + Rate Limit Check

This is the control and safety layer. It decides whether the user is allowed to perform an action, whether the user is within usage limits, and whether the agent needs explicit user approval before continuing.

Questions this layer answers:

- Can this user run another agent task?
- Can this user access Google Calendar?
- Can this user access Google Tasks?
- Is this user over their daily limit?
- Does this action require confirmation?
- Is this action read-only or does it mutate external state?
- Does this tool call need a connected account?

Examples:

- Reading today's calendar may be allowed if the Google account is connected.
- Creating a calendar event should require approval before the final write.
- Sending a push notification can be allowed for system reminders.
- Running too many agent jobs in one day can be blocked or delayed.

The result of this layer should be durable. Store decisions in `rate_limit_events`, `audit_logs`, and the relevant `agent_runs` or `scheduled_jobs` row.

## Create `agent_run` / `scheduled_job`

This is the state creation layer. Before the agent starts working, the backend creates a Supabase record so the system can track the task from request to completion.

Use `agent_runs` for immediate tasks.

Examples:

- "Summarize my day."
- "Review my tasks."
- "Find a calendar slot for this meeting."
- "Generate a weekly progress summary."

Use `scheduled_jobs` for future or recurring tasks.

Examples:

- "Every morning, send my agenda."
- "Remind me to review goals every Sunday."
- "Refresh my memory index after file uploads."
- "Send a push notification before an important event."

These records allow Flutter, support tools, and backend logs to answer:

- What is running?
- Who started it?
- What status is it in?
- Did QStash deliver it?
- Did the worker finish it?
- What tools did it call?
- Did it fail, and why?

Recurring jobs are represented by `cron_jobs` and `cron_job_executions`.
`cron_jobs` stores the definition: `name`, cron `schedule`, whitelisted `task`,
JSON `payload`, enabled state, retry/timeout controls, `last_run_at`, and
`next_run_at`. `cron_job_executions` stores each run's status, attempts, logs,
result, error, timing, and any linked `agent_run_id`.

## Upstash QStash

QStash is the queue and scheduling layer. It delivers jobs to the FastAPI worker reliably and prevents the Edge Function from waiting while the agent works.

QStash responsibilities:

- Deliver immediate jobs to the worker.
- Deliver delayed jobs at a future time.
- Support retries when the worker fails or times out.
- Handle webhook delivery to worker endpoints.
- Support scheduled or recurring workflows where needed.

QStash should carry only the data needed to locate the durable Supabase state, usually ids like `agent_run_id`, `scheduled_job_id`, and `user_id`. The worker should load full context from Supabase.

## FastAPI Worker

The FastAPI worker is the main backend worker. It receives jobs from QStash, loads the user's context, runs the agent, calls tools, updates the database, and sends notifications.

FastAPI responsibilities:

- Verify QStash signatures or shared worker secrets.
- Load `agent_runs` or `scheduled_jobs`.
- Poll due `cron_jobs`, claim them atomically, execute whitelisted tasks, and record execution logs.
- Load user context from Supabase Postgres and pgvector memory.
- Run the OpenAI Agents SDK.
- Execute approved tool calls.
- Update statuses, results, errors, and audit logs.
- Write Realtime-visible progress updates.
- Send Firebase Cloud Messaging notifications.

Most serious backend logic lives here because worker tasks can take longer than Edge Function requests.

## OpenAI Agents SDK

The OpenAI Agents SDK is the agent orchestration layer. It helps the agent reason, plan, call tools, use guardrails, manage steps, hand off between specialists, and produce final responses.

The Agents SDK should run inside the FastAPI worker under BluePill's permission and safety rules.

The Agents SDK owns:

- Agent instructions and orchestration.
- Tool call planning.
- Guardrails and structured outputs.
- Agent step execution.
- Final response generation.

The Agents SDK should not directly own:

- The whole app architecture.
- User identity.
- Permission policy.
- Billing or rate limits.
- Database ownership rules.
- External account authorization.

BluePill owns those concerns through Supabase Auth, Edge Functions, RLS, worker code, and audit logs.

## Tool Layer

The tool layer is where the agent reads information and takes action. In v1, tools can be direct Python functions inside the FastAPI worker. Later, MCP can standardize those tools behind a common protocol.

### Supabase Postgres

Supabase Postgres stores structured app data.

Examples:

- User profiles
- Tasks
- Goals
- Habits
- Check-ins
- AI check-in streaks
- Progress logs
- Agent conversations
- Agent messages
- `agent_runs`
- `scheduled_jobs`
- `connected_accounts`
- `tool_permissions`
- `agent_action_approvals`
- `rate_limit_events`
- `audit_logs`

### pgvector Memory

pgvector memory stores searchable long-term memory.

Examples:

- "User prefers meetings after 10 AM."
- "User is working on Project BluePill."
- "User likes short daily summaries."
- "User struggles with consistency after late nights."

The worker retrieves relevant memory before or during agent execution and can write new memory after important interactions.

### Supabase Storage

Supabase Storage stores files, images, documents, attachments, exports, and user-uploaded content.

Examples:

- Chat attachments
- Uploaded PDFs
- Images sent to the agent
- Generated exports
- Documents used for memory extraction

### Google Calendar

Google Calendar lets the agent read availability, suggest meeting times, summarize the user's schedule, and create events after approval.

Read examples:

- "What does my day look like?"
- "Find free slots tomorrow."
- "Summarize my meetings this week."

Write examples:

- "Create this event."
- "Move this meeting."
- "Add attendees."

Calendar writes should require user approval unless the user has explicitly configured an automation rule.

### Google Tasks

Google Tasks lets the agent create, update, and manage user tasks.

Examples:

- Create a task from a chat message.
- Update task due dates.
- Mark a task complete.
- Sync agent-created tasks into the user's Google task list.

### Firebase Cloud Messaging

Firebase Cloud Messaging sends push notifications to the user's phone or desktop.

Examples:

- "Your morning agenda is ready."
- "Approve this calendar event?"
- "Reminder: Review your goals."
- "Your weekly summary is ready."

FCM sends should happen from the worker or another trusted backend environment, not from Flutter with server credentials.

### MCP Later

MCP is the future standardized tool interface. In v1, tools can be direct FastAPI worker functions. Later, MCP can organize tools like calendar, tasks, memory, files, notes, email, and custom APIs behind a common protocol.

MCP is useful when BluePill needs:

- A consistent tool contract.
- Tool discovery.
- Cleaner separation between agent orchestration and tool implementations.
- More external integrations.

## Audit Logs + Realtime Updates

Audit logs and Realtime updates form the trust and visibility layer.

Audit logs record what the agent did.

Examples:

- Agent searched memory.
- Agent checked calendar availability.
- Agent created a task.
- User approved a calendar event.
- Worker sent a push notification.
- Rate limit blocked an agent run.

Realtime updates show progress in Flutter.

Examples:

- Agent started.
- Checking your calendar.
- Found a free slot.
- Waiting for approval.
- Event created.
- Agent run failed.
- Weekly summary is ready.

The user should never be left wondering whether the agent is working, waiting, blocked, or finished.

## Flutter UI Feedback

The final result returns to the user through Flutter. The user sees the agent answer, progress, approvals, notifications, and history.

Flutter should show:

- Agent response text.
- Streaming or step-based progress.
- Tool activity summaries.
- Approval cards for risky actions.
- Success and failure states.
- Notification history where useful.
- Audit-visible history for important actions.

## Production Rules

- Keep secrets out of Flutter.
- Every Flutter request carries a Supabase JWT.
- Edge Functions validate identity and create durable state before queueing work.
- Edge Functions stay fast.
- QStash delivers work to the worker.
- The worker runs the agent and tools.
- The Agents SDK orchestrates agent behavior but does not replace app permissions.
- Tool writes require explicit policy checks and, when needed, user approval.
- Important actions write audit logs.
- Long-running progress is visible through Realtime updates.

## Repository Structure

```text
flutter/                     Flutter app root
flutter/lib/                 Flutter UI and client-safe app services
flutter/lib/services/agent_gateway_service.dart
                              Flutter client for Edge Function and worker calls
supabase/schema.sql          Database, RLS, pgvector, Storage, Realtime
supabase/functions/          Supabase Edge Functions API gateway
supabase/functions/_shared/  Shared auth, permissions, audit, QStash helpers
supabase/functions/agent-chat/index.ts
                              Creates agent_runs, publishes to QStash
supabase/functions/schedule-job/index.ts
                              Creates scheduled_jobs, publishes to QStash
supabase/functions/approve-action/index.ts
                              Handles user approval decisions
worker/app/                  FastAPI worker
worker/app/main.py           FastAPI app entry point
worker/app/security/         QStash/shared-secret verification
worker/app/api/              HTTP endpoints
worker/app/api/agent_chat.py
                              POST /agent/chat (direct worker entry point)
worker/app/api/cron_jobs.py
                              CRUD /cron/jobs, GET /cron/jobs/{id}/executions
worker/app/jobs/             Job processors
worker/app/jobs/agent_runs.py
                              Processes agent_runs from QStash or FastAPI
worker/app/jobs/scheduled_jobs.py
                              Processes scheduled_jobs, delegates to agent_runs
worker/app/jobs/cron_scheduler.py
                              Polls and claims due cron jobs
worker/app/agents/           OpenAI Agents SDK orchestration boundary
worker/app/services/         Supabase, context, and audit services
worker/app/tools/            Postgres, memory, Storage, Google, FCM, MCP tools
```
