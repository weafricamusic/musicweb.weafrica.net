-- AI Generations
-- Tracks async AI music generation requests initiated by Artists / DJs.

create extension if not exists pgcrypto;

create table if not exists public.ai_generations (
  id uuid primary key default gen_random_uuid(),

  user_id text not null,
  creator_type text not null check (creator_type in ('artist','dj')),
  creator_id text not null,

  provider text not null default 'pipedream_suno',
  provider_job_id text,

  status text not null default 'queued' check (status in ('queued','running','succeeded','failed')),

  title text,
  prompt text not null,
  genre text,
  mood text,
  length_seconds int,

  result_audio_url text,
  result_track_id text,

  error text,
  meta jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists ai_generations_user_created_at_idx on public.ai_generations (user_id, created_at desc);
create index if not exists ai_generations_creator_created_at_idx on public.ai_generations (creator_type, creator_id, created_at desc);
create index if not exists ai_generations_status_created_at_idx on public.ai_generations (status, created_at desc);
create index if not exists ai_generations_provider_job_id_idx on public.ai_generations (provider, provider_job_id);

-- Keep updated_at fresh.
create or replace function public.set_updated_at_ai_generations()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'set_updated_at_ai_generations'
  ) then
    create trigger set_updated_at_ai_generations
      before update on public.ai_generations
      for each row
      execute function public.set_updated_at_ai_generations();
  end if;
end $$;

alter table public.ai_generations enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_generations'
      and policyname = 'deny_all_ai_generations'
  ) then
    create policy deny_all_ai_generations
      on public.ai_generations
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.ai_generations from anon, authenticated;
grant select, insert, update on table public.ai_generations to service_role;
