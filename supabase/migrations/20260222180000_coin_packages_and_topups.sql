-- COIN PURCHASE SYSTEM (CONSUMER)
-- - coin_packages: server-authoritative list of purchasable coin bundles
-- - apply_coin_topup_paychangu(): idempotent wallet credit + payment status update
--
-- This project uses Firebase Auth UIDs as TEXT in DB (e.g. wallets.user_id).

create extension if not exists pgcrypto;

create table if not exists public.coin_packages (
  id text primary key,
  title text not null,
  coins bigint not null check (coins > 0),
  price numeric not null check (price > 0),
  currency text not null default 'MWK',
  bonus_coins bigint not null default 0 check (bonus_coins >= 0),
  active boolean not null default true,
  sort_order int not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists coin_packages_active_sort_idx
  on public.coin_packages (active, sort_order asc);

alter table public.coin_packages enable row level security;

do $$
begin
  create policy "Public read active coin packages" on public.coin_packages
    for select
    to anon, authenticated
    using (active = true);
exception
  when duplicate_object then null;
end $$;

-- Seed starter packages (adjust pricing/coins as needed).
-- NOTE: Price currency is MWK by default.
insert into public.coin_packages (id, title, coins, bonus_coins, price, currency, active, sort_order)
values
  ('starter',  'Starter',  200,  0,  1000, 'MWK', true, 10),
  ('silver',   'Silver',   500,  50,  2000, 'MWK', true, 20),
  ('gold',     'Gold',    1200, 150,  4000, 'MWK', true, 30),
  ('platinum', 'Platinum', 3000, 600,  9000, 'MWK', true, 40)
on conflict (id) do update set
  title = excluded.title,
  coins = excluded.coins,
  bonus_coins = excluded.bonus_coins,
  price = excluded.price,
  currency = excluded.currency,
  active = excluded.active,
  sort_order = excluded.sort_order,
  updated_at = now();

-- Atomic + idempotent: apply a verified PayChangu coin topup.
--
-- Contract:
-- - Caller (Edge Function) must verify tx_ref with PayChangu.
-- - This function will:
--   - lock the payments row
--   - ensure purpose='coin_topup' and provider='paychangu'
--   - ensure it hasn't been verified already
--   - validate amount/currency vs provider-verified values
--   - credit wallets.user_id with package coins (coins + bonus_coins)
--   - mark payments row as success/failed and set verified_at
create or replace function public.apply_coin_topup_paychangu(
  p_tx_ref text,
  p_success boolean,
  p_verified_amount numeric,
  p_verified_currency text,
  p_provider_reference text,
  p_provider_status text,
  p_raw jsonb
)
returns table (
  ok boolean,
  idempotent boolean,
  tx_ref text,
  user_id text,
  credited_coins bigint,
  new_balance bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  pay record;
  pkg record;
  pkg_id text;
  expected_amount numeric;
  expected_currency text;
  coins_to_credit bigint;
  balance bigint;
begin
  if p_tx_ref is null or length(trim(p_tx_ref)) = 0 then
    raise exception 'missing_tx_ref' using errcode = 'P0001';
  end if;

  select *
    into pay
    from public.payments
    where provider = 'paychangu'
      and tx_ref = trim(p_tx_ref)
    for update;

  if not found then
    return query select false, false, trim(p_tx_ref), null::text, 0::bigint, 0::bigint;
    return;
  end if;

  if coalesce(pay.purpose, '') <> 'coin_topup' then
    -- Not our payment type; ignore without mutating.
    return query select false, false, trim(p_tx_ref), pay.user_id::text, 0::bigint, 0::bigint;
    return;
  end if;

  if pay.verified_at is not null then
    select w.coin_balance into balance from public.wallets w where w.user_id = pay.user_id;
    return query select true, true, trim(p_tx_ref), pay.user_id::text, 0::bigint, coalesce(balance, 0)::bigint;
    return;
  end if;

  expected_amount := pay.amount;
  expected_currency := coalesce(nullif(trim(pay.currency::text), ''), 'MWK');

  -- Derive package_id from metadata.
  pkg_id := nullif(trim((pay.metadata->>'package_id')::text), '');
  if pkg_id is null then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('error', 'missing_package_id', 'raw', p_raw),
      updated_at = now()
    where id = pay.id;

    return query select true, false, trim(p_tx_ref), pay.user_id::text, 0::bigint, 0::bigint;
    return;
  end if;

  select * into pkg
    from public.coin_packages
    where id = pkg_id
      and active = true;

  if not found then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('error', 'unknown_package', 'package_id', pkg_id, 'raw', p_raw),
      updated_at = now()
    where id = pay.id;

    return query select true, false, trim(p_tx_ref), pay.user_id::text, 0::bigint, 0::bigint;
    return;
  end if;

  -- Ensure the payment row itself matches the package catalog (server-authoritative).
  if pay.amount <> pkg.price or upper(expected_currency) <> upper(pkg.currency::text) then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'error', 'package_mismatch',
        'package_id', pkg_id,
        'expected_amount', pkg.price,
        'expected_currency', pkg.currency,
        'raw', p_raw
      ),
      updated_at = now()
    where id = pay.id;

    return query select true, false, trim(p_tx_ref), pay.user_id::text, 0::bigint, 0::bigint;
    return;
  end if;

  -- Provider verification.
  if not p_success then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('raw', p_raw),
      updated_at = now()
    where id = pay.id;

    return query select true, false, trim(p_tx_ref), pay.user_id::text, 0::bigint, 0::bigint;
    return;
  end if;

  if p_verified_amount < expected_amount or upper(coalesce(nullif(trim(p_verified_currency), ''), 'MWK')) <> upper(expected_currency) then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'error', 'verification_mismatch',
        'verified_amount', p_verified_amount,
        'verified_currency', p_verified_currency,
        'raw', p_raw
      ),
      updated_at = now()
    where id = pay.id;

    return query select true, false, trim(p_tx_ref), pay.user_id::text, 0::bigint, 0::bigint;
    return;
  end if;

  coins_to_credit := (pkg.coins + coalesce(pkg.bonus_coins, 0))::bigint;

  insert into public.wallets(user_id, coin_balance)
  values (pay.user_id::text, 0)
  on conflict (user_id) do nothing;

  update public.wallets
    set coin_balance = coin_balance + coins_to_credit,
        updated_at = now()
    where user_id = pay.user_id
    returning coin_balance into balance;

  update public.payments set
    status = 'success',
    provider_reference = p_provider_reference,
    provider_status = p_provider_status,
    verified_at = now(),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'package_id', pkg_id,
      'credited_coins', coins_to_credit,
      'raw', p_raw
    ),
    updated_at = now()
  where id = pay.id;

  return query select true, false, trim(p_tx_ref), pay.user_id::text, coins_to_credit, coalesce(balance, 0)::bigint;
end;
$$;

revoke all on function public.apply_coin_topup_paychangu(text, boolean, numeric, text, text, text, jsonb) from public;

notify pgrst, 'reload schema';
