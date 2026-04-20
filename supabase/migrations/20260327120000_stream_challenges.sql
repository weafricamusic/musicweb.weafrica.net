-- Stream challenges (battle invitations) for Live tab
--
-- Notes:
-- - This project uses Firebase UID strings as TEXT in public.profiles.id.
-- - public.live_sessions.id is UUID.
-- - This migration creates a service-role-managed table similar to stream_sessions.

-- Ensure uuid generator exists (best-effort; Supabase typically has pgcrypto enabled).
do $$
begin
  begin
    create extension if not exists pgcrypto;
  exception when insufficient_privilege then
    null;
  end;
end $$;

create table if not exists public.stream_challenges (
  id uuid primary key default gen_random_uuid(),
  challenger_id text not null,
  target_id text not null,
  live_room_id uuid not null references public.live_sessions(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired')),
  message text,
  metadata jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.stream_challenges
  add column if not exists challenger_id text,
  add column if not exists target_id text,
  add column if not exists live_room_id uuid,
  add column if not exists status text,
  add column if not exists message text,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists expires_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Normalize nulls on existing rows (idempotent safety).
update public.stream_challenges
set
  status = coalesce(nullif(btrim(status), ''), 'pending'),
  metadata = coalesce(metadata, '{}'::jsonb),
  expires_at = coalesce(expires_at, now() + interval '5 minutes'),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  status is null
  or btrim(status) = ''
  or metadata is null
  or expires_at is null
  or created_at is null
  or updated_at is null;

do $$
begin
  begin
    alter table public.stream_challenges
      drop constraint if exists stream_challenges_status_check;
  exception when undefined_object then
    null;
  end;

  alter table public.stream_challenges
    add constraint stream_challenges_status_check
    check (status in ('pending', 'accepted', 'declined', 'expired'));
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_stream_challenges_target_status
  on public.stream_challenges(target_id, status);
create index if not exists idx_stream_challenges_challenger_status
  on public.stream_challenges(challenger_id, status);
create index if not exists idx_stream_challenges_expires_at
  on public.stream_challenges(expires_at);
create index if not exists idx_stream_challenges_live_room
  on public.stream_challenges(live_room_id);

-- Touch updated_at on update (function exists in this repo; created in live migrations).
drop trigger if exists trg_stream_challenges_touch on public.stream_challenges;
create trigger trg_stream_challenges_touch
before update on public.stream_challenges
for each row execute function public._touch_updated_at();

-- RLS: keep client roles out; service-role (Edge/Nest) bypasses RLS.
alter table public.stream_challenges enable row level security;

-- Deny all from anon/authenticated (reads/writes via service role only).
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'stream_challenges'
      and policyname = 'deny_all_stream_challenges'
  ) then
    create policy deny_all_stream_challenges
      on public.stream_challenges
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.stream_challenges from anon, authenticated;
