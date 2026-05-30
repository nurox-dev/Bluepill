-- Project BluePill database schema.
-- Run this in the Supabase SQL editor after creating your project.

create extension if not exists "pgcrypto";
create schema if not exists extensions;
create extension if not exists "vector" with schema extensions;
alter extension vector set schema extensions;

do $$ begin
  create type public.goal_type as enum ('life', 'yearly', 'monthly', 'weekly');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.goal_status as enum ('active', 'paused', 'completed', 'archived');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.task_priority as enum ('high', 'medium', 'low');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.task_category as enum ('study', 'work', 'health', 'finance', 'personal', 'career');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.task_status as enum ('pending', 'completed', 'missed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.habit_frequency as enum ('daily', 'weekly', 'custom');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.habit_log_status as enum ('completed', 'missed', 'partial');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.checkin_type as enum ('morning', 'afternoon', 'night', 'weekly');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.feedback_type as enum ('suggestion', 'motivation', 'warning', 'weekly_summary');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.agent_run_status as enum ('queued', 'running', 'completed', 'failed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.scheduled_job_status as enum ('scheduled', 'queued', 'running', 'completed', 'failed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.cron_job_execution_status as enum ('running', 'succeeded', 'failed', 'timed_out', 'cancelled', 'skipped');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.agent_approval_status as enum ('pending', 'approved', 'rejected', 'expired', 'executed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.connected_account_status as enum ('connected', 'expired', 'revoked', 'error');
exception when duplicate_object then null;
end $$;

create table if not exists public.users_profile (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null,
  location_city text,
  dob date,
  dream_goal text not null,
  skills text[] default '{}',
  interests text[] default '{}',
  education_status text,
  "current_role" text,
  identity_stage text,
  goal_categories text[] default '{}',
  barriers text[] default '{}',
  strengths text[] default '{}',
  skills_to_learn text[] default '{}',
  future_vision text,
  success_definition text,
  yearly_goal text,
  main_struggle text,
  desired_habits text[] default '{}',
  motivation_style text default 'friendly',
  wake_time time,
  sleep_time time,
  created_at timestamptz not null default now()
);

-- Keep existing Supabase projects in sync with profile data written by
-- onboarding and settings. Fresh projects get these from the table above.
alter table if exists public.users_profile
  add column if not exists name text,
  add column if not exists location_city text,
  add column if not exists dob date,
  add column if not exists dream_goal text,
  add column if not exists skills text[] default '{}',
  add column if not exists interests text[] default '{}',
  add column if not exists education_status text,
  add column if not exists "current_role" text,
  add column if not exists identity_stage text,
  add column if not exists goal_categories text[] default '{}',
  add column if not exists barriers text[] default '{}',
  add column if not exists strengths text[] default '{}',
  add column if not exists skills_to_learn text[] default '{}',
  add column if not exists future_vision text,
  add column if not exists success_definition text,
  add column if not exists yearly_goal text,
  add column if not exists main_struggle text,
  add column if not exists desired_habits text[] default '{}',
  add column if not exists motivation_style text default 'friendly',
  add column if not exists wake_time time,
  add column if not exists sleep_time time;

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  goal_type public.goal_type not null default 'weekly',
  parent_goal_id uuid references public.goals(id) on delete set null,
  deadline date,
  progress_percent numeric not null default 0 check (progress_percent >= 0 and progress_percent <= 100),
  status public.goal_status not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references public.goals(id) on delete set null,
  title text not null,
  description text,
  priority public.task_priority not null default 'medium',
  category public.task_category not null default 'personal',
  status public.task_status not null default 'pending',
  due_date date,
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes > 0),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table if exists public.tasks
  add column if not exists goal_id uuid references public.goals(id) on delete set null;

alter table if exists public.tasks
  add column if not exists google_task_id text,
  add column if not exists google_task_list_id text,
  add column if not exists google_task_updated_at timestamptz;

create unique index if not exists idx_tasks_user_google_task
  on public.tasks(user_id, google_task_list_id, google_task_id)
  where google_task_id is not null;

create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  category text default 'personal',
  frequency public.habit_frequency not null default 'daily',
  target text,
  current_streak integer not null default 0,
  completion_rate numeric not null default 0 check (completion_rate >= 0 and completion_rate <= 100),
  created_at timestamptz not null default now()
);

create table if not exists public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null default current_date,
  status public.habit_log_status not null default 'completed',
  notes text,
  created_at timestamptz not null default now(),
  unique (habit_id, date)
);

create table if not exists public.checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type public.checkin_type not null,
  question text not null,
  user_answer text not null,
  ai_extracted_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.ai_checkin_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  best_streak integer not null default 0 check (best_streak >= 0),
  last_checkin_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.progress_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null default current_date,
  tasks_completed integer not null default 0,
  tasks_missed integer not null default 0,
  habits_completed integer not null default 0,
  habits_missed integer not null default 0,
  focus_score integer check (focus_score is null or (focus_score >= 0 and focus_score <= 10)),
  mood text,
  blocker text,
  life_score integer not null default 0 check (life_score >= 0 and life_score <= 100),
  ai_summary text,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

create table if not exists public.ai_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feedback_type public.feedback_type not null,
  message text not null,
  related_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.agent_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.agent_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.agent_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  text text not null,
  attachments jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table if exists public.agent_conversations
  drop column if exists persona_id,
  drop column if exists persona_label;

alter table if exists public.agent_messages
  drop column if exists persona_label;

create table if not exists public.agent_memory_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null check (source_type in ('profile', 'conversation', 'checkin', 'task', 'goal', 'habit', 'file', 'system')),
  source_table text,
  source_id uuid,
  storage_bucket text,
  storage_path text,
  title text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.agent_memory_chunks (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.agent_memory_sources(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  embedding extensions.vector(1536),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid references public.agent_conversations(id) on delete set null,
  message_id uuid references public.agent_messages(id) on delete set null,
  run_type text not null default 'chat',
  status public.agent_run_status not null default 'queued',
  queue_provider text not null default 'qstash',
  external_run_id text,
  qstash_message_id text,
  idempotency_key text,
  input jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  tool_names text[] not null default '{}',
  attempts integer not null default 0 check (attempts >= 0),
  error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.scheduled_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agent_run_id uuid references public.agent_runs(id) on delete set null,
  job_type text not null,
  status public.scheduled_job_status not null default 'scheduled',
  queue_provider text not null default 'qstash',
  external_job_id text,
  idempotency_key text,
  scheduled_for timestamptz not null,
  payload jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  attempts integer not null default 0 check (attempts >= 0),
  error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cron_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  schedule text not null check (length(trim(schedule)) > 0),
  task text not null check (length(trim(task)) > 0),
  payload jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  timezone text not null default 'UTC',
  max_retries integer not null default 0 check (max_retries >= 0 and max_retries <= 10),
  timeout_seconds integer not null default 300 check (timeout_seconds > 0 and timeout_seconds <= 3600),
  retry_delay_seconds integer not null default 30 check (retry_delay_seconds >= 0 and retry_delay_seconds <= 3600),
  idempotency_key text,
  last_run_at timestamptz,
  next_run_at timestamptz,
  last_status public.cron_job_execution_status,
  last_error text,
  locked_at timestamptz,
  locked_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cron_job_executions (
  id uuid primary key default gen_random_uuid(),
  cron_job_id uuid not null references public.cron_jobs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  agent_run_id uuid references public.agent_runs(id) on delete set null,
  scheduled_for timestamptz not null,
  task text not null,
  payload jsonb not null default '{}'::jsonb,
  status public.cron_job_execution_status not null default 'running',
  attempts integer not null default 0 check (attempts >= 0),
  max_retries integer not null default 0 check (max_retries >= 0 and max_retries <= 10),
  timeout_seconds integer not null default 300 check (timeout_seconds > 0 and timeout_seconds <= 3600),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  result jsonb not null default '{}'::jsonb,
  error text,
  logs jsonb not null default '[]'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.connected_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('google', 'apple', 'firebase', 'mcp')),
  account_label text,
  account_email text,
  scopes text[] not null default '{}',
  status public.connected_account_status not null default 'connected',
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider, account_email)
);

create table if not exists public.tool_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tool_name text not null,
  action text not null,
  allowed boolean not null default false,
  requires_approval boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, tool_name, action)
);

create table if not exists public.agent_action_approvals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agent_run_id uuid references public.agent_runs(id) on delete cascade,
  scheduled_job_id uuid references public.scheduled_jobs(id) on delete set null,
  tool_name text not null,
  action text not null,
  status public.agent_approval_status not null default 'pending',
  proposed_payload jsonb not null default '{}'::jsonb,
  decision_payload jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.rate_limit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  endpoint text not null,
  rate_limit_key text not null,
  action text not null,
  allowed boolean not null,
  cost integer not null default 1 check (cost > 0),
  limit_count integer check (limit_count is null or limit_count >= 0),
  window_seconds integer check (window_seconds is null or window_seconds > 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  actor_type text not null check (actor_type in ('user', 'edge_function', 'worker', 'system')),
  event_type text not null,
  target_table text,
  target_id uuid,
  agent_run_id uuid references public.agent_runs(id) on delete set null,
  scheduled_job_id uuid references public.scheduled_jobs(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web', 'macos')),
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

insert into storage.buckets (id, name, public)
values ('agent-attachments', 'agent-attachments', false)
on conflict (id) do nothing;

create index if not exists idx_goals_user_type on public.goals(user_id, goal_type, status);
create index if not exists idx_tasks_user_due_status on public.tasks(user_id, due_date, status);
create index if not exists idx_habits_user on public.habits(user_id);
create index if not exists idx_habit_logs_user_date on public.habit_logs(user_id, date);
create index if not exists idx_checkins_user_created on public.checkins(user_id, created_at desc);
create index if not exists idx_ai_checkin_streaks_last_date on public.ai_checkin_streaks(user_id, last_checkin_date desc);
create index if not exists idx_progress_logs_user_date on public.progress_logs(user_id, date desc);
create index if not exists idx_ai_feedback_user_created on public.ai_feedback(user_id, created_at desc);
create index if not exists idx_agent_conversations_user_updated on public.agent_conversations(user_id, updated_at desc);
create index if not exists idx_agent_messages_conversation_created on public.agent_messages(conversation_id, created_at);
create index if not exists idx_agent_memory_sources_user_type on public.agent_memory_sources(user_id, source_type, created_at desc);
create index if not exists idx_agent_memory_chunks_user_source on public.agent_memory_chunks(user_id, source_id);
create index if not exists idx_agent_memory_chunks_embedding on public.agent_memory_chunks using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists idx_agent_runs_user_status on public.agent_runs(user_id, status, created_at desc);
create unique index if not exists idx_agent_runs_idempotency on public.agent_runs(user_id, idempotency_key)
  where idempotency_key is not null;
create index if not exists idx_scheduled_jobs_user_status on public.scheduled_jobs(user_id, status, scheduled_for);
create unique index if not exists idx_scheduled_jobs_idempotency on public.scheduled_jobs(user_id, idempotency_key)
  where idempotency_key is not null;
create index if not exists idx_cron_jobs_user_enabled on public.cron_jobs(user_id, enabled, next_run_at);
create index if not exists idx_cron_jobs_due on public.cron_jobs(next_run_at, created_at)
  where enabled = true;
create unique index if not exists idx_cron_jobs_idempotency on public.cron_jobs(user_id, idempotency_key)
  where idempotency_key is not null;
create index if not exists idx_cron_job_executions_job_created on public.cron_job_executions(cron_job_id, created_at desc);
create index if not exists idx_cron_job_executions_user_status on public.cron_job_executions(user_id, status, created_at desc);
create index if not exists idx_connected_accounts_user_provider on public.connected_accounts(user_id, provider, status);
create index if not exists idx_tool_permissions_user_tool on public.tool_permissions(user_id, tool_name, action);
create index if not exists idx_agent_action_approvals_user_status on public.agent_action_approvals(user_id, status, created_at desc);
create index if not exists idx_agent_action_approvals_run on public.agent_action_approvals(agent_run_id, status);
create index if not exists idx_rate_limit_events_user_created on public.rate_limit_events(user_id, created_at desc);
create index if not exists idx_rate_limit_events_key_created on public.rate_limit_events(rate_limit_key, created_at desc);
create index if not exists idx_audit_logs_user_created on public.audit_logs(user_id, created_at desc);
create index if not exists idx_audit_logs_agent_run on public.audit_logs(agent_run_id, created_at desc);
create index if not exists idx_device_tokens_user_enabled on public.device_tokens(user_id, enabled);

create or replace function public.match_agent_memory(
  match_user_id uuid,
  query_embedding extensions.vector(1536),
  match_count integer default 8,
  similarity_threshold double precision default 0.2
)
returns table (
  chunk_id uuid,
  source_id uuid,
  content text,
  metadata jsonb,
  similarity double precision
)
language sql
stable
set search_path = public, extensions
as $$
  select
    agent_memory_chunks.id as chunk_id,
    agent_memory_chunks.source_id,
    agent_memory_chunks.content,
    agent_memory_chunks.metadata,
    1 - (agent_memory_chunks.embedding <=> query_embedding) as similarity
  from public.agent_memory_chunks
  where agent_memory_chunks.user_id = match_user_id
    and (auth.uid() = match_user_id or auth.role() = 'service_role')
    and agent_memory_chunks.embedding is not null
    and 1 - (agent_memory_chunks.embedding <=> query_embedding) >= similarity_threshold
  order by agent_memory_chunks.embedding <=> query_embedding
  limit match_count;
$$;

create or replace function public.claim_due_cron_jobs(
  p_limit integer default 10,
  p_worker_id text default null,
  p_now timestamptz default now(),
  p_lock_ttl_seconds integer default 600
)
returns setof public.cron_jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with due_jobs as (
    select id
    from public.cron_jobs
    where enabled = true
      and next_run_at is not null
      and next_run_at <= p_now
      and (
        locked_at is null
        or locked_at < p_now - make_interval(secs => greatest(p_lock_ttl_seconds, 1))
      )
    order by next_run_at asc, created_at asc
    for update skip locked
    limit greatest(p_limit, 1)
  )
  update public.cron_jobs jobs
  set
    locked_at = p_now,
    locked_by = coalesce(nullif(p_worker_id, ''), 'worker'),
    updated_at = p_now
  from due_jobs
  where jobs.id = due_jobs.id
  returning jobs.*;
end;
$$;

revoke all on function public.claim_due_cron_jobs(integer, text, timestamptz, integer) from public;
grant execute on function public.claim_due_cron_jobs(integer, text, timestamptz, integer) to service_role;

alter table public.users_profile enable row level security;
alter table public.goals enable row level security;
alter table public.tasks enable row level security;
alter table public.habits enable row level security;
alter table public.habit_logs enable row level security;
alter table public.checkins enable row level security;
alter table public.ai_checkin_streaks enable row level security;
alter table public.progress_logs enable row level security;
alter table public.ai_feedback enable row level security;
alter table public.agent_conversations enable row level security;
alter table public.agent_messages enable row level security;
alter table public.agent_memory_sources enable row level security;
alter table public.agent_memory_chunks enable row level security;
alter table public.agent_runs enable row level security;
alter table public.scheduled_jobs enable row level security;
alter table public.cron_jobs enable row level security;
alter table public.cron_job_executions enable row level security;
alter table public.connected_accounts enable row level security;
alter table public.tool_permissions enable row level security;
alter table public.agent_action_approvals enable row level security;
alter table public.rate_limit_events enable row level security;
alter table public.audit_logs enable row level security;
alter table public.device_tokens enable row level security;

drop policy if exists "Users can read own profile" on public.users_profile;
create policy "Users can read own profile" on public.users_profile
  for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own profile" on public.users_profile;
create policy "Users can insert own profile" on public.users_profile
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own profile" on public.users_profile;
create policy "Users can update own profile" on public.users_profile
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can delete own profile" on public.users_profile;
create policy "Users can delete own profile" on public.users_profile
  for delete using (auth.uid() = user_id);

drop policy if exists "Users can manage own goals" on public.goals;
create policy "Users can manage own goals" on public.goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own tasks" on public.tasks;
create policy "Users can manage own tasks" on public.tasks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own habits" on public.habits;
create policy "Users can manage own habits" on public.habits
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own habit logs" on public.habit_logs;
create policy "Users can manage own habit logs" on public.habit_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own checkins" on public.checkins;
create policy "Users can manage own checkins" on public.checkins
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own ai checkin streak" on public.ai_checkin_streaks;
create policy "Users can manage own ai checkin streak" on public.ai_checkin_streaks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own progress logs" on public.progress_logs;
create policy "Users can manage own progress logs" on public.progress_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own ai feedback" on public.ai_feedback;
create policy "Users can manage own ai feedback" on public.ai_feedback
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own agent conversations" on public.agent_conversations;
create policy "Users can manage own agent conversations" on public.agent_conversations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own agent messages" on public.agent_messages;
create policy "Users can manage own agent messages" on public.agent_messages
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own memory sources" on public.agent_memory_sources;
create policy "Users can manage own memory sources" on public.agent_memory_sources
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own memory chunks" on public.agent_memory_chunks;
create policy "Users can manage own memory chunks" on public.agent_memory_chunks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can read own agent runs" on public.agent_runs;
create policy "Users can read own agent runs" on public.agent_runs
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own scheduled jobs" on public.scheduled_jobs;
create policy "Users can read own scheduled jobs" on public.scheduled_jobs
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own cron jobs" on public.cron_jobs;
create policy "Users can read own cron jobs" on public.cron_jobs
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own cron job executions" on public.cron_job_executions;
create policy "Users can read own cron job executions" on public.cron_job_executions
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own connected accounts" on public.connected_accounts;
create policy "Users can read own connected accounts" on public.connected_accounts
  for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own connected accounts" on public.connected_accounts;
create policy "Users can insert own connected accounts" on public.connected_accounts
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own connected accounts" on public.connected_accounts;
create policy "Users can update own connected accounts" on public.connected_accounts
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can read own tool permissions" on public.tool_permissions;
create policy "Users can read own tool permissions" on public.tool_permissions
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own action approvals" on public.agent_action_approvals;
create policy "Users can read own action approvals" on public.agent_action_approvals
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own rate limit events" on public.rate_limit_events;
create policy "Users can read own rate limit events" on public.rate_limit_events
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own audit logs" on public.audit_logs;
create policy "Users can read own audit logs" on public.audit_logs
  for select using (auth.uid() = user_id);

drop policy if exists "Users can manage own device tokens" on public.device_tokens;
create policy "Users can manage own device tokens" on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can manage own agent attachments" on storage.objects;
create policy "Users can manage own agent attachments" on storage.objects
  for all
  using (
    bucket_id = 'agent-attachments' and
    (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'agent-attachments' and
    (storage.foldername(name))[1] = auth.uid()::text
  );

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'agent_messages'
    ) then
      alter publication supabase_realtime add table public.agent_messages;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'agent_runs'
    ) then
      alter publication supabase_realtime add table public.agent_runs;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'scheduled_jobs'
    ) then
      alter publication supabase_realtime add table public.scheduled_jobs;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'cron_jobs'
    ) then
      alter publication supabase_realtime add table public.cron_jobs;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'cron_job_executions'
    ) then
      alter publication supabase_realtime add table public.cron_job_executions;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'audit_logs'
    ) then
      alter publication supabase_realtime add table public.audit_logs;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'agent_action_approvals'
    ) then
      alter publication supabase_realtime add table public.agent_action_approvals;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ai_feedback'
    ) then
      alter publication supabase_realtime add table public.ai_feedback;
    end if;
  end if;
end $$;
