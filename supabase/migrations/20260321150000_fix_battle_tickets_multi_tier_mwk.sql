-- Fix battle_tickets schema for Sprint 3 ticketing foundation
--
-- Moves battle tickets to:
-- - MWK pricing (real money)
-- - multi-tier per battle (standard/vip/priority)
--
-- Notes:
-- - This migration is idempotent.
-- - It tolerates earlier coin-based columns from 20260321120000_battle_tickets.sql.

do $$
begin
  if to_regclass('public.battle_tickets') is null then
    return;
  end if;

  -- Tier + pricing fields
  alter table public.battle_tickets
    add column if not exists tier text,
    add column if not exists price_amount numeric(12,2),
    add column if not exists price_currency text not null default 'MWK',
    add column if not exists sale_start_at timestamptz,
    add column if not exists sale_end_at timestamptz,
    add column if not exists is_active boolean not null default true;
end $$;

-- Rename quantity_sold -> sold_quantity (if present)
do $$
begin
  if to_regclass('public.battle_tickets') is null then
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'battle_tickets'
      and column_name = 'quantity_sold'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'battle_tickets'
      and column_name = 'sold_quantity'
  ) then
    execute 'alter table public.battle_tickets rename column quantity_sold to sold_quantity';
  end if;
end $$;

-- Ensure sold_quantity exists (some schemas already had it)
do $$
begin
  if to_regclass('public.battle_tickets') is null then
    return;
  end if;

  alter table public.battle_tickets
    add column if not exists sold_quantity int not null default 0;
end $$;

-- Backfill: tier + price_amount
do $$
begin
  if to_regclass('public.battle_tickets') is null then
    return;
  end if;

  update public.battle_tickets
    set tier = coalesce(nullif(trim(tier), ''), 'standard')
  where tier is null or length(trim(tier)) = 0;

  -- If migrating from the coin-based schema, map price_coins -> price_amount
  -- (best-effort to preserve a value; adjust manually if needed).
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'battle_tickets'
      and column_name = 'price_coins'
  ) then
    execute 'update public.battle_tickets '
            'set price_amount = coalesce(price_amount, (price_coins::numeric)) '
            'where price_amount is null';
  end if;

  update public.battle_tickets
    set price_amount = coalesce(price_amount, 0)
  where price_amount is null;
end $$;

-- Drop legacy unique index (single config per battle) and replace with (battle_id, tier)
drop index if exists battle_tickets_battle_id_uniq;
create unique index if not exists battle_tickets_battle_id_tier_uniq
  on public.battle_tickets (battle_id, tier);

-- Replace constraints to match new schema
do $$
declare
  c record;
begin
  if to_regclass('public.battle_tickets') is null then
    return;
  end if;

  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.battle_tickets'::regclass
      and conname in (
        'battle_tickets_price_nonneg',
        'battle_tickets_quantity_bounds'
      )
  loop
    execute format('alter table public.battle_tickets drop constraint %I', c.conname);
  end loop;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.battle_tickets'::regclass
      and conname = 'battle_tickets_tier_check'
  ) then
    alter table public.battle_tickets
      add constraint battle_tickets_tier_check
      check (tier in ('standard','vip','priority'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.battle_tickets'::regclass
      and conname = 'battle_tickets_price_amount_nonneg'
  ) then
    alter table public.battle_tickets
      add constraint battle_tickets_price_amount_nonneg
      check (price_amount >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.battle_tickets'::regclass
      and conname = 'battle_tickets_quantity_bounds_v2'
  ) then
    alter table public.battle_tickets
      add constraint battle_tickets_quantity_bounds_v2
      check (quantity_total > 0 and sold_quantity >= 0 and sold_quantity <= quantity_total);
  end if;
end $$;

-- Drop legacy coin pricing column if present.
do $$
begin
  if to_regclass('public.battle_tickets') is null then
    return;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'battle_tickets'
      and column_name = 'price_coins'
  ) then
    execute 'alter table public.battle_tickets drop column price_coins';
  end if;
end $$;

notify pgrst, 'reload schema';
