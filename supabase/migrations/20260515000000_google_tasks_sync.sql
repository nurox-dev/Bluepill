alter table if exists public.tasks
  add column if not exists google_task_id text,
  add column if not exists google_task_list_id text,
  add column if not exists google_task_updated_at timestamptz;

create unique index if not exists idx_tasks_user_google_task
  on public.tasks(user_id, google_task_list_id, google_task_id)
  where google_task_id is not null;
