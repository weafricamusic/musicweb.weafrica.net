-- DJ EVENTS + ARTIST WALLETS (Schema cache fix)
--
-- Fixes PostgREST errors like:
--   "Could not find the table public.dj_events in the schema cache"
--   "Could not find the table public.artist_wallets in the schema cache"
--
-- Notes:
-- - These errors typically happen when the table does not exist in the target DB,
--   OR when PostgREST schema cache has not been refreshed after migrations,
--   OR when the calling role (anon/authenticated) lacks SELECT privileges.
-- - This migration is idempotent and safe to apply repeatedly.

-- Ensure artist_wallets exists and is visible to anon/authenticated (read-only).
create table if not exists public.artist_wallets (
  artist_id text primary key,
  earned_coins bigint not null default 0,
  withdrawable_coins bigint not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.artist_wallets
  add column if not exists earned_coins bigint not null default 0;

alter table public.artist_wallets
  add column if not exists withdrawable_coins bigint not null default 0;

alter table public.artist_wallets
  add column if not exists updated_at timestamptz not null default now();

alter table public.artist_wallets enable row level security;

do $$
begin
  create policy "Public read artist wallets" on public.artist_wallets
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

grant select on table public.artist_wallets to anon, authenticated;

-- DJ EVENTS (minimal event stream for DJ dashboard / scheduling).
create table if not exists public.dj_events (
  id uuid primary key default gen_random_uuid(),
  dj_id text not null,
  event_type text not null default 'generic',
  title text,
  description text,
  starts_at timestamptz,
  ends_at timestamptz,
  live_id text,
  channel_id text,
  status text not null default 'scheduled',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dj_events_dj_id_created_at_idx
  on public.dj_events (dj_id, created_at desc);

create index if not exists dj_events_starts_at_idx
  on public.dj_events (starts_at desc);

create index if not exists dj_events_status_idx
  on public.dj_events (status);

alter table public.dj_events enable row level security;

do $$
begin
  create policy "Public read dj events" on public.dj_events
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

grant select on table public.dj_events to anon, authenticated;

grant all on table public.dj_events to service_role;
grant all on table public.artist_wallets to service_role;
