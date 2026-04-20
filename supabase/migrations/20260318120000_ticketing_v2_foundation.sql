-- Ticketing v2 foundation
--
-- Adds: creator ownership fields, consumer purchase fields, inventory reservations,
-- coin↔cash conversion rates (multi-currency), payout config, and audit tables.
--
-- Non-negotiables:
-- - ticketing_* remains the single source of truth
-- - clients never write base tables (writes via SECURITY DEFINER RPCs)
-- - PayChangu webhook finalizes cash/mixed payments

create extension if not exists pgcrypto;

-- Ensure the shared updated_at trigger helper exists.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- --------------------
-- ticketing_events (creator ownership + online gating + currency)
-- --------------------

do $$
begin
  if to_regclass('public.ticketing_events') is null then
    return;
  end if;

  alter table public.ticketing_events
    add column if not exists host_user_id text,
    add column if not exists host_role text,
    add column if not exists is_online boolean not null default false,
    add column if not exists access_channel_id text,
    add column if not exists currency_code text,
    add column if not exists sales_enabled boolean not null default true,
    add column if not exists max_tickets_per_user int,
    add column if not exists published_at timestamptz;
end $$;

create index if not exists ticketing_events_host_user_id_idx
  on public.ticketing_events (host_user_id);

create index if not exists ticketing_events_published_at_idx
  on public.ticketing_events (published_at desc);

-- --------------------
-- ticketing_ticket_types (inventory reservations + per-user limits)
-- --------------------

do $$
begin
  if to_regclass('public.ticketing_ticket_types') is null then
    return;
  end if;

  alter table public.ticketing_ticket_types
    add column if not exists quantity_reserved int not null default 0,
    add column if not exists sales_enabled boolean not null default true,
    add column if not exists max_per_user int;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_types'::regclass
      and conname = 'ticketing_ticket_types_quantity_reserved_nonneg'
  ) then
    alter table public.ticketing_ticket_types
      add constraint ticketing_ticket_types_quantity_reserved_nonneg
      check (quantity_reserved >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_types'::regclass
      and conname = 'ticketing_ticket_types_sold_plus_reserved_le_total'
  ) then
    alter table public.ticketing_ticket_types
      add constraint ticketing_ticket_types_sold_plus_reserved_le_total
      check ((quantity_sold + quantity_reserved) <= quantity_total);
  end if;
end $$;

create index if not exists ticketing_ticket_types_sales_enabled_idx
  on public.ticketing_ticket_types (sales_enabled);

-- --------------------
-- ticketing_ticket_orders (consumer ownership, mixed payments, idempotency, TTL)
-- --------------------

do $$
declare
  c record;
begin
  if to_regclass('public.ticketing_ticket_orders') is null then
    return;
  end if;

  alter table public.ticketing_ticket_orders
    add column if not exists buyer_user_id text,
    add column if not exists payment_mode text,
    add column if not exists idempotency_key text,
    add column if not exists expires_at timestamptz,
    add column if not exists coins_used bigint not null default 0,
    add column if not exists coins_value_amount_cents int not null default 0,
    add column if not exists cash_due_amount_cents int not null default 0,
    add column if not exists paid_at timestamptz,
    add column if not exists cancelled_at timestamptz,
    add column if not exists refunded_at timestamptz,
    add column if not exists expired_at timestamptz,
    add column if not exists failure_reason text;

  -- Upgrade the order status check constraint to include v2 lifecycle states.
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_orders'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
      and pg_get_constraintdef(oid) ilike '%pending%'
      and pg_get_constraintdef(oid) ilike '%paid%'
  loop
    execute format('alter table public.ticketing_ticket_orders drop constraint %I', c.conname);
  end loop;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_orders'::regclass
      and conname = 'ticketing_ticket_orders_status_check_v2'
  ) then
    alter table public.ticketing_ticket_orders
      add constraint ticketing_ticket_orders_status_check_v2
      check (status in ('pending','paid','cancelled','refunded','expired','failed'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_orders'::regclass
      and conname = 'ticketing_ticket_orders_payment_mode_check'
  ) then
    alter table public.ticketing_ticket_orders
      add constraint ticketing_ticket_orders_payment_mode_check
      check (payment_mode is null or payment_mode in ('free','coins','cash','mixed'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_orders'::regclass
      and conname = 'ticketing_ticket_orders_coins_used_nonneg'
  ) then
    alter table public.ticketing_ticket_orders
      add constraint ticketing_ticket_orders_coins_used_nonneg
      check (coins_used >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_orders'::regclass
      and conname = 'ticketing_ticket_orders_coins_value_nonneg'
  ) then
    alter table public.ticketing_ticket_orders
      add constraint ticketing_ticket_orders_coins_value_nonneg
      check (coins_value_amount_cents >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ticketing_ticket_orders'::regclass
      and conname = 'ticketing_ticket_orders_cash_due_bounds'
  ) then
    alter table public.ticketing_ticket_orders
      add constraint ticketing_ticket_orders_cash_due_bounds
      check (
        cash_due_amount_cents >= 0
        and cash_due_amount_cents <= total_amount_cents
        and coins_value_amount_cents <= total_amount_cents
      );
  end if;
end $$;

create index if not exists ticketing_ticket_orders_buyer_user_id_idx
  on public.ticketing_ticket_orders (buyer_user_id);

create unique index if not exists ticketing_ticket_orders_buyer_idempotency_uniq
  on public.ticketing_ticket_orders (buyer_user_id, idempotency_key)
  where buyer_user_id is not null and idempotency_key is not null;

create unique index if not exists ticketing_ticket_orders_payment_ref_uniq
  on public.ticketing_ticket_orders (payment_provider, payment_reference)
  where payment_provider is not null and payment_reference is not null;

create index if not exists ticketing_ticket_orders_pending_expires_at_idx
  on public.ticketing_ticket_orders (expires_at)
  where status = 'pending';

-- --------------------
-- ticketing_tickets (ownership + immutability)
-- --------------------

do $$
begin
  if to_regclass('public.ticketing_tickets') is null then
    return;
  end if;

  alter table public.ticketing_tickets
    add column if not exists owner_user_id text,
    add column if not exists voided_at timestamptz;
end $$;

create or replace function public.ticketing_tickets_enforce_immutability()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if new.event_id is distinct from old.event_id
    or new.ticket_type_id is distinct from old.ticket_type_id
    or new.order_id is distinct from old.order_id
    or new.code is distinct from old.code
    or new.owner_user_id is distinct from old.owner_user_id
    or new.issued_at is distinct from old.issued_at
  then
    raise exception 'immutable_ticket_fields' using errcode = 'P0001';
  end if;

  if old.checked_in_at is not null and new.checked_in_at is null then
    raise exception 'checked_in_at_cannot_be_cleared' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.ticketing_tickets') is null then
    return;
  end if;

  if not exists (select 1 from pg_trigger where tgname = 'ticketing_tickets_immutability_guard') then
    create trigger ticketing_tickets_immutability_guard
      before update on public.ticketing_tickets
      for each row
      execute function public.ticketing_tickets_enforce_immutability();
  end if;
end $$;

-- --------------------
-- coin_conversion_rates (fixed rates per currency; rational to avoid rounding drift)
-- --------------------

create table if not exists public.coin_conversion_rates (
  currency_code text primary key,
  minor_units_per_coin_numer bigint not null check (minor_units_per_coin_numer > 0),
  minor_units_per_coin_denom bigint not null check (minor_units_per_coin_denom > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists coin_conversion_rates_active_idx
  on public.coin_conversion_rates (active);

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'coin_conversion_rates_set_updated_at') then
    create trigger coin_conversion_rates_set_updated_at
      before update on public.coin_conversion_rates
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

alter table public.coin_conversion_rates enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'coin_conversion_rates'
      and policyname = 'deny_all_coin_conversion_rates'
  ) then
    create policy deny_all_coin_conversion_rates
      on public.coin_conversion_rates
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Seed initial fixed rates (can be adjusted later; orders snapshot coin value at purchase time).
insert into public.coin_conversion_rates (currency_code, minor_units_per_coin_numer, minor_units_per_coin_denom, active)
values
  ('USD', 1, 5, true),
  ('MWK', 348, 1, true),
  ('ZAR', 19, 5, true)
on conflict (currency_code) do update set
  minor_units_per_coin_numer = excluded.minor_units_per_coin_numer,
  minor_units_per_coin_denom = excluded.minor_units_per_coin_denom,
  active = excluded.active,
  updated_at = now();

-- --------------------
-- ticketing_config (global fixed payout cut + reservation TTL)
-- --------------------

create table if not exists public.ticketing_config (
  id int primary key check (id = 1),
  platform_cut_bps int not null default 1500 check (platform_cut_bps >= 0 and platform_cut_bps <= 10000),
  reservation_ttl_seconds int not null default 600 check (reservation_ttl_seconds > 0 and reservation_ttl_seconds <= 86400),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ticketing_config_set_updated_at') then
    create trigger ticketing_config_set_updated_at
      before update on public.ticketing_config
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

alter table public.ticketing_config enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_config'
      and policyname = 'deny_all_ticketing_config'
  ) then
    create policy deny_all_ticketing_config
      on public.ticketing_config
      for all
      using (false)
      with check (false);
  end if;
end $$;

insert into public.ticketing_config (id, platform_cut_bps, reservation_ttl_seconds)
values (1, 1500, 600)
on conflict (id) do update set
  platform_cut_bps = excluded.platform_cut_bps,
  reservation_ttl_seconds = excluded.reservation_ttl_seconds,
  updated_at = now();

-- --------------------
-- ticketing_checkin_logs (append-only audit)
-- --------------------

create table if not exists public.ticketing_checkin_logs (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.ticketing_events(id) on delete cascade,
  ticket_code text not null,
  ticket_id uuid references public.ticketing_tickets(id),
  admin_email text,
  ok boolean not null default false,
  reason text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ticketing_checkin_logs_event_created_idx
  on public.ticketing_checkin_logs (event_id, created_at desc);

create index if not exists ticketing_checkin_logs_ticket_code_idx
  on public.ticketing_checkin_logs (ticket_code);

create index if not exists ticketing_checkin_logs_ticket_id_idx
  on public.ticketing_checkin_logs (ticket_id);

alter table public.ticketing_checkin_logs enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_checkin_logs'
      and policyname = 'deny_all_ticketing_checkin_logs'
  ) then
    create policy deny_all_ticketing_checkin_logs
      on public.ticketing_checkin_logs
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- --------------------
-- ticketing_refunds (append-only operational log)
-- --------------------

create table if not exists public.ticketing_refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.ticketing_ticket_orders(id) on delete cascade,
  provider text,
  provider_ref text,
  status text not null default 'requested' check (status in ('requested','processing','succeeded','failed','cancelled')),
  amount_cents int not null check (amount_cents >= 0),
  currency_code text not null,
  requested_by_admin_email text,
  reason text,
  raw jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists ticketing_refunds_order_id_idx
  on public.ticketing_refunds (order_id);

create unique index if not exists ticketing_refunds_provider_ref_uniq
  on public.ticketing_refunds (provider, provider_ref)
  where provider is not null and provider_ref is not null;

alter table public.ticketing_refunds enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_refunds'
      and policyname = 'deny_all_ticketing_refunds'
  ) then
    create policy deny_all_ticketing_refunds
      on public.ticketing_refunds
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- --------------------
-- ticketing payouts (batch + per-event items)
-- --------------------

create table if not exists public.ticketing_payout_batches (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'draft' check (status in ('draft','approved','paid','cancelled')),
  created_by_admin_email text,
  approved_by_admin_email text,
  approved_at timestamptz,
  paid_at timestamptz,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ticketing_payout_batches_set_updated_at') then
    create trigger ticketing_payout_batches_set_updated_at
      before update on public.ticketing_payout_batches
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

alter table public.ticketing_payout_batches enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_payout_batches'
      and policyname = 'deny_all_ticketing_payout_batches'
  ) then
    create policy deny_all_ticketing_payout_batches
      on public.ticketing_payout_batches
      for all
      using (false)
      with check (false);
  end if;
end $$;

create table if not exists public.ticketing_payout_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.ticketing_payout_batches(id) on delete cascade,
  event_id uuid not null references public.ticketing_events(id) on delete cascade,
  host_user_id text,
  currency_code text not null,
  gross_amount_cents int not null default 0 check (gross_amount_cents >= 0),
  refunds_amount_cents int not null default 0 check (refunds_amount_cents >= 0),
  platform_fee_amount_cents int not null default 0 check (platform_fee_amount_cents >= 0),
  net_amount_cents int not null default 0 check (net_amount_cents >= 0),
  status text not null default 'pending' check (status in ('pending','approved','paid','cancelled')),
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ticketing_payout_items_set_updated_at') then
    create trigger ticketing_payout_items_set_updated_at
      before update on public.ticketing_payout_items
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

create index if not exists ticketing_payout_items_batch_id_idx
  on public.ticketing_payout_items (batch_id);

create index if not exists ticketing_payout_items_event_id_idx
  on public.ticketing_payout_items (event_id);

alter table public.ticketing_payout_items enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_payout_items'
      and policyname = 'deny_all_ticketing_payout_items'
  ) then
    create policy deny_all_ticketing_payout_items
      on public.ticketing_payout_items
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';
