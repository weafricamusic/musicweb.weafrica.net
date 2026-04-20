-- Add subscriptions.plan_code for legacy clients/admin UI expecting it.
-- Some dashboards query public.subscriptions.plan_code; older alignment migration did not include it.

create extension if not exists pgcrypto;

alter table if exists public.subscriptions
  add column if not exists plan_code text,
  add column if not exists plan_name text;

-- Backfill plan_name from existing `name` column when present.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscriptions'
      and column_name = 'name'
  ) then
    update public.subscriptions
    set plan_name = coalesce(plan_name, name)
    where plan_name is null;
  end if;
end $$;

-- Keep plan_name in sync on insert/update (best-effort; safe if legacy clients write `name`).
create or replace function public.tg_subscriptions_sync_plan_name()
returns trigger
language plpgsql
as $$
begin
  if new.plan_name is null then
    new.plan_name = new.name;
  end if;
  return new;
end;
$$;

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'subscriptions'
  ) then
    if not exists (
      select 1
      from pg_trigger
      where tgname = 'subscriptions_sync_plan_name'
    ) then
      create trigger subscriptions_sync_plan_name
      before insert or update on public.subscriptions
      for each row
      execute function public.tg_subscriptions_sync_plan_name();
    end if;
  end if;
end $$;

-- Backfill from subscription_plans when link exists.
do $$
declare
  plans_sub_id_type text;
  subs_id_type text;
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'subscriptions'
  ) then
    -- Prefer explicit link: subscription_plans.subscription_id -> subscriptions.id
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'subscription_plans'
        and column_name = 'subscription_id'
    ) then
    select data_type into plans_sub_id_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_plans'
      and column_name = 'subscription_id';

    select data_type into subs_id_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscriptions'
      and column_name = 'id';

    -- Only join when types match (some legacy deployments use uuid ids).
    if plans_sub_id_type is not null and subs_id_type is not null and plans_sub_id_type = subs_id_type then
      update public.subscriptions s
      set plan_code = sp.plan_id
      from public.subscription_plans sp
      where s.plan_code is null
        and sp.subscription_id = s.id;
    else
      raise notice 'Skipping subscriptions.plan_code backfill join due to incompatible types: subscription_plans.subscription_id=% vs subscriptions.id=%', plans_sub_id_type, subs_id_type;
    end if;
    end if;

    -- Fallback mapping by name.
    update public.subscriptions
    set plan_code = case
      when lower(trim(name)) = 'free' then 'free'
      when lower(trim(name)) = 'premium' then 'premium'
      when lower(trim(name)) = 'platinum' then 'platinum'
      else null
    end
    where plan_code is null;
  end if;
end $$;

-- Keep plan_code unique when present; allow multiple NULLs.
do $$
begin
  begin
    create unique index if not exists subscriptions_plan_code_unique
      on public.subscriptions (plan_code);
  exception
    when unique_violation then
      raise notice 'Could not create subscriptions_plan_code_unique because public.subscriptions contains duplicate plan_code values. Dedupe subscriptions.plan_code, then re-run index creation.';
    when duplicate_table then null;
    when duplicate_object then null;
  end;
end $$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
