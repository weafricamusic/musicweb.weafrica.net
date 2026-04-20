-- Fix wallet schema drift: ensure expected columns exist on public.wallets.
-- Idempotent: safe to run multiple times.

create extension if not exists pgcrypto;
-- Ensure table exists (creates with the expected shape if missing).
create table if not exists public.wallets (
  user_id text primary key,
  coin_balance numeric not null default 0,
  cash_balance numeric not null default 0,
  total_earned numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Add any missing columns on existing tables.
alter table public.wallets
  add column if not exists coin_balance numeric not null default 0,
  add column if not exists cash_balance numeric not null default 0,
  add column if not exists total_earned numeric not null default 0,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();
-- Ensure Firebase UID storage: user_id must be TEXT.
-- Note: if `wallets.user_id` was previously UUID, ALTER TYPE can fail if policies depend on it.
-- Drop policies first (they'll be recreated below).
do $$
declare
  r record;
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='wallets') then
    for r in (
      select policyname from pg_policies where schemaname='public' and tablename='wallets'
    ) loop
      execute format('drop policy if exists %I on public.wallets', r.policyname);
    end loop;
  end if;
end $$;
do $$
declare
  v_type text;
begin
  select data_type into v_type
  from information_schema.columns
  where table_schema='public' and table_name='wallets' and column_name='user_id';

  if v_type is not null and v_type <> 'text' then
    execute 'alter table public.wallets alter column user_id type text using user_id::text';
  end if;
end $$;
alter table public.wallets enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='wallets' and policyname='wallets_select_own'
  ) then
    create policy wallets_select_own
      on public.wallets
      for select
      to authenticated
      using (auth.uid()::text = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='wallets' and policyname='wallets_insert_own'
  ) then
    create policy wallets_insert_own
      on public.wallets
      for insert
      to authenticated
      with check (auth.uid()::text = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='wallets' and policyname='wallets_update_own'
  ) then
    create policy wallets_update_own
      on public.wallets
      for update
      to authenticated
      using (auth.uid()::text = user_id)
      with check (auth.uid()::text = user_id);
  end if;
end $$;
grant select, insert, update on public.wallets to authenticated;
-- Ask PostgREST to reload its schema cache (helpful for PGRST204).
notify pgrst, 'reload schema';
