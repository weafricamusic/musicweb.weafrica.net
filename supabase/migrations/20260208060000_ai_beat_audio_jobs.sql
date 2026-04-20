-- Step 13+ — AI Beat Audio (MP3) Jobs
-- Queue + storage metadata for server-side beat audio generation.
--
-- Notes:
-- - Server-only: all writes should happen via Edge Function using service_role.
-- - Storage: private bucket + signed URLs returned from Edge Function.

-- Needed for gen_random_uuid()
create extension if not exists pgcrypto;
-- Optional pricing table (server-side reference).
create table if not exists public.ai_pricing (
  action text primary key,
  coin_cost integer not null default 0 check (coin_cost >= 0),
  daily_free_limit integer not null default 0 check (daily_free_limit >= 0),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.ai_pricing enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_pricing'
      and policyname = 'deny_all_ai_pricing'
  ) then
    create policy deny_all_ai_pricing
      on public.ai_pricing
      for all
      using (false)
      with check (false);
  end if;
end $$;
revoke all on table public.ai_pricing from anon, authenticated;
-- Job table
create table if not exists public.ai_beat_audio_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  status text not null default 'queued', -- queued|running|succeeded|failed
  provider text not null default 'replicate',
  provider_prediction_id text,

  style text,
  bpm int,
  mood text,
  duration_seconds int,
  prompt text,
  seed int,

  storage_bucket text,
  storage_path text,
  output_mime text,
  output_bytes bigint,

  monetization jsonb,
  error text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ai_beat_audio_jobs_user_created_at_idx
  on public.ai_beat_audio_jobs (user_id, created_at desc);
create index if not exists ai_beat_audio_jobs_status_created_at_idx
  on public.ai_beat_audio_jobs (status, created_at desc);
alter table public.ai_beat_audio_jobs enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_beat_audio_jobs'
      and policyname = 'deny_all_ai_beat_audio_jobs'
  ) then
    create policy deny_all_ai_beat_audio_jobs
      on public.ai_beat_audio_jobs
      for all
      using (false)
      with check (false);
  end if;
end $$;
revoke all on table public.ai_beat_audio_jobs from anon, authenticated;
-- Keep updated_at fresh
create or replace function public._touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists ai_beat_audio_jobs_touch_updated_at on public.ai_beat_audio_jobs;
create trigger ai_beat_audio_jobs_touch_updated_at
before update on public.ai_beat_audio_jobs
for each row execute procedure public._touch_updated_at();
-- Storage bucket for generated MP3s (private + signed URLs from Edge Function)
insert into storage.buckets (id, name, public)
values ('ai_beats', 'ai_beats', false)
on conflict (id) do nothing;
-- Pricing row for audio generation (costly; no free daily quota)
insert into public.ai_pricing (action, coin_cost, daily_free_limit, enabled, updated_at)
values ('beat_audio_generation', 250, 0, true, now())
on conflict (action) do update
  set coin_cost = excluded.coin_cost,
      daily_free_limit = excluded.daily_free_limit,
      enabled = excluded.enabled,
      updated_at = now();
revoke all on function public._touch_updated_at() from public;
grant execute on function public._touch_updated_at() to service_role;
