alter table if exists public.users_profile
  add column if not exists identity_stage text,
  add column if not exists goal_categories text[] default '{}',
  add column if not exists barriers text[] default '{}',
  add column if not exists strengths text[] default '{}',
  add column if not exists skills_to_learn text[] default '{}',
  add column if not exists future_vision text,
  add column if not exists success_definition text;
