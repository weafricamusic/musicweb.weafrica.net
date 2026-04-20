-- Payout destinations for DJs/Artists (bank account, mobile money).
-- Stored as explicit destinations that can be marked as default.
-- This migration is idempotent and safe across projects.

create extension if not exists pgcrypto;

create table if not exists public.payout_destinations (
  id uuid primary key default gen_random_uuid(),

  owner_type text not null check (owner_type in ('dj','artist')),
  owner_id text not null,

  kind text not null check (kind in ('bank','mobile_money')),

  -- Optional friendly label (e.g. "Airtel Money", "NBS Bank").
  label text,

  -- Bank fields
  bank_name text,
  bank_account_name text,
  bank_account_number text,
  bank_branch text,

  -- Mobile money fields
  mobile_network text,
  mobile_number text,
  mobile_account_name text,

  is_default boolean not null default false,

  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Backfill/align columns for legacy environments (best-effort).
alter table if exists public.payout_destinations
  add column if not exists owner_type text,
  add column if not exists owner_id text,
  add column if not exists kind text,
  add column if not exists label text,
  add column if not exists bank_name text,
  add column if not exists bank_account_name text,
  add column if not exists bank_account_number text,
  add column if not exists bank_branch text,
  add column if not exists mobile_network text,
  add column if not exists mobile_number text,
  add column if not exists mobile_account_name text,
  add column if not exists is_default boolean,
  add column if not exists meta jsonb,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

update public.payout_destinations set is_default = coalesce(is_default, false) where is_default is null;
update public.payout_destinations set meta = coalesce(meta, '{}'::jsonb) where meta is null;
update public.payout_destinations set created_at = coalesce(created_at, now()) where created_at is null;
update public.payout_destinations set updated_at = coalesce(updated_at, now()) where updated_at is null;

alter table public.payout_destinations alter column is_default set default false;
alter table public.payout_destinations alter column meta set default '{}'::jsonb;
alter table public.payout_destinations alter column created_at set default now();
alter table public.payout_destinations alter column updated_at set default now();

-- Constraints (avoid failing if legacy data violates them).
do $$
begin
  begin
    alter table public.payout_destinations
      add constraint payout_destinations_owner_type_check
      check (owner_type in ('dj','artist'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.payout_destinations
      add constraint payout_destinations_kind_check
      check (kind in ('bank','mobile_money'));
  exception when duplicate_object then null;
  end;
end $$;

create index if not exists payout_destinations_owner_idx on public.payout_destinations (owner_type, owner_id);
create index if not exists payout_destinations_kind_idx on public.payout_destinations (kind);
create index if not exists payout_destinations_default_idx on public.payout_destinations (owner_type, owner_id) where is_default;

-- Ensure at most one default destination per owner.
create unique index if not exists payout_destinations_one_default_per_owner
  on public.payout_destinations (owner_type, owner_id)
  where is_default;

-- Link withdrawals to a destination (optional) for auditability.
alter table if exists public.withdrawals
  add column if not exists payout_destination_id uuid;

create index if not exists withdrawals_payout_destination_idx on public.withdrawals (payout_destination_id);

alter table public.payout_destinations enable row level security;

-- Keep consistent with other finance tables: deny all for non-service-role clients.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'payout_destinations'
      and policyname = 'deny_all_payout_destinations'
  ) then
    create policy deny_all_payout_destinations
      on public.payout_destinations
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
