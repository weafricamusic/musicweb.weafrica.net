-- Minimal DJ wallets table (compat)
--
-- Observed error:
-- - Wallet storage is not configured yet (missing table: dj_wallets)
--
-- This migration creates a small, flexible wallet table.
-- RLS is deny-all; service_role can access.

create extension if not exists pgcrypto;

create table if not exists public.dj_wallets (
  id uuid primary key default gen_random_uuid(),
  dj_id text,
  user_id text,
  coins integer not null default 0 check (coins >= 0),
  locked_coins integer not null default 0 check (locked_coins >= 0),
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists dj_wallets_dj_id_idx on public.dj_wallets (dj_id);
create index if not exists dj_wallets_user_id_idx on public.dj_wallets (user_id);
create index if not exists dj_wallets_created_at_idx on public.dj_wallets (created_at desc);

-- If a DJ has a single wallet, this unique index helps enforce it
-- but allows null dj_id rows in edge cases.
create unique index if not exists dj_wallets_dj_id_unique
  on public.dj_wallets (dj_id)
  where dj_id is not null and length(trim(dj_id)) > 0;

alter table public.dj_wallets enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'dj_wallets'
      and policyname = 'deny_all_dj_wallets'
  ) then
    create policy deny_all_dj_wallets
      on public.dj_wallets
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.dj_wallets from anon, authenticated;
grant all on table public.dj_wallets to service_role;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
