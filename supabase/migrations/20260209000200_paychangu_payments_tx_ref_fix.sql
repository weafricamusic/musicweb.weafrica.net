-- Compatibility fix: ensure `paychangu_payments.tx_ref` exists for older deployments.
--
-- The Edge Function uses `tx_ref` for idempotent upserts. Some older tables may
-- be missing the column entirely (or lack a unique constraint), causing
-- PostgREST schema-cache errors like:
--   "Could not find the 'tx_ref' column of 'paychangu_payments' in the schema cache"

do $$
begin
  -- Supabase typically has pgcrypto enabled, but make this migration robust.
  create extension if not exists pgcrypto;
exception
  when insufficient_privilege then
    -- Ignore: extension may already exist or permissions may be restricted.
    null;
end $$;

alter table public.paychangu_payments
  add column if not exists tx_ref text;

-- Backfill tx_ref for existing rows if the table previously used a different PK.
-- Use gen_random_uuid() when available; otherwise fall back to md5(random()).
do $$
begin
  update public.paychangu_payments
  set tx_ref = coalesce(tx_ref, gen_random_uuid()::text)
  where tx_ref is null;
exception
  when undefined_function then
    update public.paychangu_payments
    set tx_ref = coalesce(tx_ref, md5(random()::text || clock_timestamp()::text))
    where tx_ref is null;
end $$;

-- De-duplicate tx_ref if historical data contains duplicates (required for UNIQUE).
do $$
begin
  with ranked as (
    select ctid,
           tx_ref,
           row_number() over (
             partition by tx_ref
             order by created_at nulls last, updated_at nulls last
           ) as rn
    from public.paychangu_payments
    where tx_ref is not null
  )
  update public.paychangu_payments p
  set tx_ref = gen_random_uuid()::text
  from ranked r
  where p.ctid = r.ctid
    and r.rn > 1;
exception
  when undefined_function then
    with ranked as (
      select ctid,
             tx_ref,
             row_number() over (
               partition by tx_ref
               order by created_at nulls last, updated_at nulls last
             ) as rn
      from public.paychangu_payments
      where tx_ref is not null
    )
    update public.paychangu_payments p
    set tx_ref = md5(random()::text || clock_timestamp()::text)
    from ranked r
    where p.ctid = r.ctid
      and r.rn > 1;
end $$;

alter table public.paychangu_payments
  alter column tx_ref set not null;

-- Ensure tx_ref is unique so upsert(onConflict: 'tx_ref') works.
do $$
declare
  has_constraint boolean;
  has_same_named_index boolean;
begin
  select exists(
    select 1
    from pg_constraint c
    where c.conname = 'paychangu_payments_tx_ref_key'
      and c.conrelid = 'public.paychangu_payments'::regclass
  ) into has_constraint;

  select exists(
    select 1
    from pg_class cls
    join pg_namespace ns on ns.oid = cls.relnamespace
    where ns.nspname = 'public'
      and cls.relname = 'paychangu_payments_tx_ref_key'
      and cls.relkind = 'i'
  ) into has_same_named_index;

  -- If either the constraint exists or a same-named unique index already exists,
  -- skip creating the constraint to avoid "relation already exists" failures.
  if not has_constraint and not has_same_named_index then
    alter table public.paychangu_payments
      add constraint paychangu_payments_tx_ref_key unique (tx_ref);
  end if;
exception
  when duplicate_object then
    null;
  when duplicate_table then
    null;
end $$;

-- Some Postgres versions / policies behave better with a UNIQUE index for ON CONFLICT.
-- This is redundant if the constraint exists, but harmless.
create unique index if not exists paychangu_payments_tx_ref_uidx
  on public.paychangu_payments (tx_ref);
