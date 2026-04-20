-- Creator payout destinations used by the mobile Earnings Hub.
-- Cross-device storage for artist and DJ bank/mobile-money payout methods.

create extension if not exists pgcrypto;

create table if not exists public.payout_destinations (
  id uuid primary key default gen_random_uuid(),
  owner_type text not null check (owner_type in ('artist', 'dj')),
  owner_id text not null,
  kind text not null check (kind in ('bank', 'mobile_money')),
  label text,
  bank_name text,
  bank_account_name text,
  bank_account_number text,
  bank_branch text,
  mobile_network text,
  mobile_number text,
  mobile_account_name text,
  is_default boolean not null default false,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

update public.payout_destinations
set is_default = coalesce(is_default, false),
    meta = coalesce(meta, '{}'::jsonb),
    created_at = coalesce(created_at, now()),
    updated_at = coalesce(updated_at, now())
where is_default is null
   or meta is null
   or created_at is null
   or updated_at is null;

alter table public.payout_destinations alter column is_default set default false;
alter table public.payout_destinations alter column meta set default '{}'::jsonb;
alter table public.payout_destinations alter column created_at set default now();
alter table public.payout_destinations alter column updated_at set default now();

create index if not exists payout_destinations_owner_idx
  on public.payout_destinations (owner_type, owner_id);

create index if not exists payout_destinations_kind_idx
  on public.payout_destinations (kind);

create index if not exists payout_destinations_default_idx
  on public.payout_destinations (owner_type, owner_id)
  where is_default;

create unique index if not exists payout_destinations_one_default_per_owner
  on public.payout_destinations (owner_type, owner_id)
  where is_default;

create unique index if not exists payout_destinations_one_kind_per_owner
  on public.payout_destinations (owner_type, owner_id, kind);

do $$
begin
  if exists (
    select 1
    from pg_proc
    where proname = 'tg_set_updated_at'
      and pg_function_is_visible(oid)
  ) and not exists (
    select 1 from pg_trigger where tgname = 'payout_destinations_set_updated_at'
  ) then
    create trigger payout_destinations_set_updated_at
      before update on public.payout_destinations
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

alter table public.payout_destinations enable row level security;
alter table public.payout_destinations force row level security;

drop policy if exists deny_all_payout_destinations on public.payout_destinations;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payout_destinations'
      and policyname = 'owners_select_payout_destinations'
  ) then
    create policy owners_select_payout_destinations
      on public.payout_destinations
      for select
      to authenticated
      using (owner_id = auth.uid()::text);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payout_destinations'
      and policyname = 'owners_insert_payout_destinations'
  ) then
    create policy owners_insert_payout_destinations
      on public.payout_destinations
      for insert
      to authenticated
      with check (
        owner_id = auth.uid()::text
        and owner_type in ('artist', 'dj')
        and kind in ('bank', 'mobile_money')
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payout_destinations'
      and policyname = 'owners_update_payout_destinations'
  ) then
    create policy owners_update_payout_destinations
      on public.payout_destinations
      for update
      to authenticated
      using (owner_id = auth.uid()::text)
      with check (
        owner_id = auth.uid()::text
        and owner_type in ('artist', 'dj')
        and kind in ('bank', 'mobile_money')
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payout_destinations'
      and policyname = 'owners_delete_payout_destinations'
  ) then
    create policy owners_delete_payout_destinations
      on public.payout_destinations
      for delete
      to authenticated
      using (owner_id = auth.uid()::text);
  end if;

  if exists (
    select 1
    from pg_proc
    where proname = 'is_platform_admin'
      and pg_function_is_visible(oid)
  ) and not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payout_destinations'
      and policyname = 'admins_manage_payout_destinations'
  ) then
    create policy admins_manage_payout_destinations
      on public.payout_destinations
      for all
      to authenticated
      using (public.is_platform_admin(auth.uid()::text))
      with check (public.is_platform_admin(auth.uid()::text));
  end if;
end $$;

notify pgrst, 'reload schema';