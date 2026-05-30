do $$ begin
  create type public.cron_job_execution_status as enum (
    'running',
    'succeeded',
    'failed',
    'timed_out',
    'cancelled',
    'skipped'
  );
exception when duplicate_object then null;
end $$;

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

create index if not exists idx_cron_jobs_user_enabled
  on public.cron_jobs(user_id, enabled, next_run_at);

create index if not exists idx_cron_jobs_due
  on public.cron_jobs(next_run_at, created_at)
  where enabled = true;

create unique index if not exists idx_cron_jobs_idempotency
  on public.cron_jobs(user_id, idempotency_key)
  where idempotency_key is not null;

create index if not exists idx_cron_job_executions_job_created
  on public.cron_job_executions(cron_job_id, created_at desc);

create index if not exists idx_cron_job_executions_user_status
  on public.cron_job_executions(user_id, status, created_at desc);

alter table public.cron_jobs enable row level security;
alter table public.cron_job_executions enable row level security;

drop policy if exists "Users can read own cron jobs" on public.cron_jobs;
create policy "Users can read own cron jobs" on public.cron_jobs
  for select using (auth.uid() = user_id);

drop policy if exists "Users can read own cron job executions" on public.cron_job_executions;
create policy "Users can read own cron job executions" on public.cron_job_executions
  for select using (auth.uid() = user_id);

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

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
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
  end if;
end $$;
