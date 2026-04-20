-- STAGE v1.1 — Rankings snapshots
--
-- Purpose:
-- - Persist precomputed leaderboards (global/country/city/genre)
-- - Keep writes service-role-only (computed server-side)
-- - Allow public read (optional auth)

create extension if not exists pgcrypto;

create table if not exists public.stage_rankings_snapshots (
  id uuid primary key default gen_random_uuid(),

  ranking_type text not null check (ranking_type in (
    'coins_earned',
    'gifts_received',
    'battle_wins',
    'followers_growth',
    'view_minutes'
  )),

  scope text not null default 'global' check (scope in (
    'global',
    'country',
    'city',
    'genre'
  )),

  scope_key text,

  period_start timestamptz not null,
  period_end timestamptz not null,
  computed_at timestamptz not null default now(),

  -- Stored as: [{ user_id: string, rank: number, score: number, meta?: object }, ...]
  entries jsonb not null,
  meta jsonb not null default '{}'::jsonb
);

-- One snapshot per (type,scope,scope_key,period), treating NULL scope_key as empty.
create unique index if not exists stage_rankings_snapshots_unique
  on public.stage_rankings_snapshots (
    ranking_type,
    scope,
    (coalesce(scope_key, '')),
    period_start,
    period_end
  );

create index if not exists stage_rankings_snapshots_period_idx
  on public.stage_rankings_snapshots (period_end desc, computed_at desc);

alter table public.stage_rankings_snapshots enable row level security;

-- Default posture: deny all mutations from anon/authenticated.
-- Reads are allowed (public leaderboards).

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'stage_rankings_snapshots'
      and policyname = 'deny_all_stage_rankings_snapshots'
  ) then
    create policy deny_all_stage_rankings_snapshots
      on public.stage_rankings_snapshots
      for all
      using (false)
      with check (false);
  end if;
end $$;

do $$
begin
  create policy "Public read stage_rankings_snapshots"
    on public.stage_rankings_snapshots
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

grant select on table public.stage_rankings_snapshots to anon, authenticated;
revoke insert, update, delete on table public.stage_rankings_snapshots from anon, authenticated;
