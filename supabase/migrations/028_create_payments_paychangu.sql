-- Generic payments table (provider-agnostic) for PayChangu and future gateways.
--
-- NOTE: This project uses Firebase Auth UIDs (text) in DB (e.g., `profiles.id`, `wallets.user_id`).

create extension if not exists pgcrypto;
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),

  user_id text not null,
  provider text not null default 'paychangu',

  -- What the payment is for: coin_topup | wallet_topup | subscription | booking | gift
  purpose text not null,

  -- Amount and currency sent to provider
  amount numeric not null,
  currency text not null,

  -- PayChangu transaction reference (tx_ref). MUST be unique.
  tx_ref text not null,

  status text not null default 'pending',
  checkout_url text,

  -- Provider verification fields
  provider_reference text,
  provider_status text,
  verified_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (provider, tx_ref)
);
create index if not exists payments_user_id_created_at_idx
  on public.payments (user_id, created_at desc);
create index if not exists payments_tx_ref_idx
  on public.payments (tx_ref);
alter table public.payments enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='payments' and policyname='payments_select_own'
  ) then
    create policy payments_select_own
      on public.payments
      for select
      to authenticated
      using (auth.uid()::text = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='payments' and policyname='payments_insert_own'
  ) then
    create policy payments_insert_own
      on public.payments
      for insert
      to authenticated
      with check (auth.uid()::text = user_id);
  end if;
end $$;
grant select, insert on public.payments to authenticated;
notify pgrst, 'reload schema';
