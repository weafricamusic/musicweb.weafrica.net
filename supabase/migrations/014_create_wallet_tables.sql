-- Wallet tables for WeAfrica Music (Firebase UID stored as TEXT)

create extension if not exists pgcrypto;
-- 1) Wallet balances
create table if not exists public.wallets (
  user_id text primary key,
  coin_balance numeric not null default 0,
  cash_balance numeric not null default 0,
  total_earned numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- 2) Wallet transaction ledger
create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  type text not null,
  amount numeric not null,
  balance_type text not null,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists wallet_transactions_user_id_created_at_idx
  on public.wallet_transactions (user_id, created_at desc);
-- 3) Withdrawals
create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  amount numeric not null,
  status text not null default 'pending',
  payment_method text not null,
  account_details jsonb not null default '{}'::jsonb,
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists withdrawal_requests_user_id_created_at_idx
  on public.withdrawal_requests (user_id, created_at desc);
-- 4) Battle earnings log
create table if not exists public.battle_earnings (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  battle_id text not null,
  amount numeric not null,
  status text not null default 'credited',
  created_at timestamptz not null default now(),
  unique (user_id, battle_id)
);
-- 5) Coin purchases log
create table if not exists public.coin_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  coin_amount integer not null,
  amount_paid numeric not null,
  payment_id text not null,
  status text not null default 'completed',
  created_at timestamptz not null default now(),
  unique (payment_id)
);
-- MVP dev RLS (NOT production-safe)
alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.battle_earnings enable row level security;
alter table public.coin_purchases enable row level security;
do $$
begin
  -- wallets
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='wallets' and policyname='mvp_public_all'
  ) then
    create policy mvp_public_all on public.wallets for all using (true) with check (true);
  end if;

  -- wallet_transactions
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='wallet_transactions' and policyname='mvp_public_all'
  ) then
    create policy mvp_public_all on public.wallet_transactions for all using (true) with check (true);
  end if;

  -- withdrawal_requests
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='withdrawal_requests' and policyname='mvp_public_all'
  ) then
    create policy mvp_public_all on public.withdrawal_requests for all using (true) with check (true);
  end if;

  -- battle_earnings
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='battle_earnings' and policyname='mvp_public_all'
  ) then
    create policy mvp_public_all on public.battle_earnings for all using (true) with check (true);
  end if;

  -- coin_purchases
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='coin_purchases' and policyname='mvp_public_all'
  ) then
    create policy mvp_public_all on public.coin_purchases for all using (true) with check (true);
  end if;
end $$;
grant select, insert, update, delete on public.wallets to anon, authenticated;
grant select, insert, update, delete on public.wallet_transactions to anon, authenticated;
grant select, insert, update, delete on public.withdrawal_requests to anon, authenticated;
grant select, insert, update, delete on public.battle_earnings to anon, authenticated;
grant select, insert, update, delete on public.coin_purchases to anon, authenticated;
