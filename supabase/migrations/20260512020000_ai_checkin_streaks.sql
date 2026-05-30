create table if not exists public.ai_checkin_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  best_streak integer not null default 0 check (best_streak >= 0),
  last_checkin_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ai_checkin_streaks_last_date
  on public.ai_checkin_streaks(user_id, last_checkin_date desc);

alter table public.ai_checkin_streaks enable row level security;

drop policy if exists "Users can manage own ai checkin streak" on public.ai_checkin_streaks;
create policy "Users can manage own ai checkin streak" on public.ai_checkin_streaks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
