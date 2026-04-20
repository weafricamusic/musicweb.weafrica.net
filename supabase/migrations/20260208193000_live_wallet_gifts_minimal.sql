-- Live gifts / wallet wiring (minimal)
--
-- Why this migration exists:
-- Some production deployments expect `public.live_gift_events` to exist.
-- This repo previously had a *placeholder* migration version 20260206000200 to match
-- remote history; using that same version locally would conflict. So we add a new
-- forward migration that creates the missing objects.
--
-- Server-only:
-- - Uses TEXT user ids (Firebase UID)
-- - RLS deny-all; Edge Function uses service_role

create extension if not exists pgcrypto;
-- Gift events emitted during live sessions/battles.
create table if not exists public.live_gift_events (
  id uuid primary key default gen_random_uuid(),
  stream_id bigint,
  battle_id text,
  from_uid text,
  to_uid text,
  gift_type text,
  coins integer not null default 0 check (coins >= 0),
  message text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Some projects created `public.live_gift_events` earlier with a different schema
-- (e.g. channel_id/from_user_id/to_host_id/gift_id/coin_cost). Ensure the legacy
-- columns used by this migration exist before creating indexes/views.
alter table public.live_gift_events
  add column if not exists stream_id bigint,
  add column if not exists battle_id text,
  add column if not exists from_uid text,
  add column if not exists to_uid text,
  add column if not exists gift_type text,
  add column if not exists coins integer not null default 0 check (coins >= 0),
  add column if not exists message text,
  add column if not exists meta jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default now();

create index if not exists live_gift_events_stream_created_idx
  on public.live_gift_events (stream_id, created_at desc);
create index if not exists live_gift_events_battle_created_idx
  on public.live_gift_events (battle_id, created_at desc);
create index if not exists live_gift_events_to_created_idx
  on public.live_gift_events (to_uid, created_at desc);
alter table public.live_gift_events enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'live_gift_events'
      and policyname = 'deny_all_live_gift_events'
  ) then
    create policy deny_all_live_gift_events
      on public.live_gift_events
      for all
      using (false)
      with check (false);
  end if;
end $$;
revoke all on table public.live_gift_events from anon, authenticated;
-- Optional compatibility view for the admin monitoring UI.
-- Only create if there isn't already a table/view named live_stream_gifts.
DO $$
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'live_stream_gifts'
  ) then
    execute $view$
      create view public.live_stream_gifts as
      select
        id,
        stream_id,
        from_uid,
        to_uid,
        gift_type,
        coins,
        message,
        meta,
        created_at
      from public.live_gift_events
      where stream_id is not null;
    $view$;

    revoke all on table public.live_stream_gifts from anon, authenticated;
    grant select on table public.live_stream_gifts to service_role;
  end if;
end $$;
