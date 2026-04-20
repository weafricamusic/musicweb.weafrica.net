-- Multi-currency cash balances (default: MWK).
-- Keeps `wallets.cash_balance` as the canonical MWK balance for backward compatibility,
-- while adding a per-currency table for future expansion.

create extension if not exists pgcrypto;
-- 1) Per-currency cash balances
create table if not exists public.wallet_cash_balances (
  user_id text not null,
  currency text not null,
  balance numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, currency)
);
create index if not exists wallet_cash_balances_user_currency_idx
  on public.wallet_cash_balances (user_id, currency);
-- 2) MVP dev RLS (NOT production-safe)
alter table public.wallet_cash_balances enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='wallet_cash_balances' and policyname='mvp_public_all'
  ) then
    create policy mvp_public_all on public.wallet_cash_balances for all using (true) with check (true);
  end if;
end $$;
grant select, insert, update, delete on public.wallet_cash_balances to anon, authenticated;
-- 3) Backfill: treat existing `wallets.cash_balance` as MWK
insert into public.wallet_cash_balances (user_id, currency, balance, created_at, updated_at)
select w.user_id, 'MWK', coalesce(w.cash_balance, 0), now(), now()
from public.wallets w
on conflict (user_id, currency)
do update set
  balance = excluded.balance,
  updated_at = now();
-- 4) Update existing RPCs to also maintain MWK row in `wallet_cash_balances`

create or replace function public.request_withdrawal(
  p_user_id text,
  p_amount numeric,
  p_payment_method text,
  p_account_details jsonb
)
returns table (
  request_id uuid,
  new_cash_balance numeric
)
language plpgsql
security definer
as $$
declare
  v_cash_balance numeric;
begin
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be > 0';
  end if;

  if p_amount < 10 then
    raise exception 'minimum withdrawal amount is 10';
  end if;

  if p_payment_method is null or length(trim(p_payment_method)) = 0 then
    raise exception 'payment_method is required';
  end if;

  insert into public.wallets (user_id, coin_balance, cash_balance, total_earned, created_at, updated_at)
  values (p_user_id, 100, 0, 0, now(), now())
  on conflict (user_id) do nothing;

  select cash_balance
    into v_cash_balance
  from public.wallets
  where user_id = p_user_id
  for update;

  if v_cash_balance < p_amount then
    raise exception 'insufficient cash balance';
  end if;

  insert into public.withdrawal_requests (
    user_id,
    amount,
    status,
    payment_method,
    account_details,
    created_at,
    updated_at
  )
  values (
    p_user_id,
    p_amount,
    'pending',
    p_payment_method,
    coalesce(p_account_details, '{}'::jsonb),
    now(),
    now()
  )
  returning id into request_id;

  update public.wallets
  set cash_balance = cash_balance - p_amount,
      updated_at = now()
  where user_id = p_user_id
  returning cash_balance into new_cash_balance;

  -- Keep MWK in sync.
  insert into public.wallet_cash_balances (user_id, currency, balance, updated_at)
  values (p_user_id, 'MWK', new_cash_balance, now())
  on conflict (user_id, currency)
  do update set balance = excluded.balance, updated_at = now();

  insert into public.wallet_transactions (
    user_id,
    type,
    amount,
    balance_type,
    description,
    metadata,
    created_at
  )
  values (
    p_user_id,
    'debit',
    p_amount,
    'cash',
    'Withdrawal request',
    jsonb_build_object(
      'request_id', request_id,
      'payment_method', p_payment_method,
      'currency', 'MWK',
      'source', 'withdrawal_request'
    ),
    now()
  );

  return;
end;
$$;
grant execute on function public.request_withdrawal(text, numeric, text, jsonb) to anon, authenticated;
create or replace function public.convert_coins_to_cash(
  p_user_id text,
  p_coins numeric,
  p_conversion_rate numeric default 1000
)
returns table (
  new_coin_balance numeric,
  new_cash_balance numeric,
  cash_received numeric
)
language plpgsql
security definer
as $$
declare
  v_coin_balance numeric;
  v_cash_balance numeric;
begin
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id is required';
  end if;

  if p_coins is null or p_coins <= 0 then
    raise exception 'coins must be > 0';
  end if;

  if p_coins < 100 then
    raise exception 'minimum conversion is 100 coins';
  end if;

  if p_conversion_rate is null or p_conversion_rate <= 0 then
    raise exception 'conversion_rate must be > 0';
  end if;

  insert into public.wallets (user_id, coin_balance, cash_balance, total_earned, created_at, updated_at)
  values (p_user_id, 100, 0, 0, now(), now())
  on conflict (user_id) do nothing;

  select coin_balance, cash_balance
    into v_coin_balance, v_cash_balance
  from public.wallets
  where user_id = p_user_id
  for update;

  if v_coin_balance < p_coins then
    raise exception 'insufficient coin balance';
  end if;

  cash_received := p_coins / p_conversion_rate;

  update public.wallets
  set coin_balance = coin_balance - p_coins,
      cash_balance = cash_balance + cash_received,
      updated_at = now()
  where user_id = p_user_id
  returning coin_balance, cash_balance
    into new_coin_balance, new_cash_balance;

  -- Keep MWK in sync.
  insert into public.wallet_cash_balances (user_id, currency, balance, updated_at)
  values (p_user_id, 'MWK', new_cash_balance, now())
  on conflict (user_id, currency)
  do update set balance = excluded.balance, updated_at = now();

  insert into public.wallet_transactions (
    user_id,
    type,
    amount,
    balance_type,
    description,
    metadata,
    created_at
  )
  values (
    p_user_id,
    'conversion',
    p_coins,
    'coin',
    'Converted coins to cash',
    jsonb_build_object(
      'conversion_rate', p_conversion_rate,
      'cash_received', cash_received,
      'currency', 'MWK',
      'coins_before', v_coin_balance,
      'coins_after', new_coin_balance,
      'cash_before', v_cash_balance,
      'cash_after', new_cash_balance,
      'source', 'convert_coins_to_cash'
    ),
    now()
  );

  return;
end;
$$;
grant execute on function public.convert_coins_to_cash(text, numeric, numeric) to anon, authenticated;
-- Ask PostgREST to reload schema cache.
notify pgrst, 'reload schema';
