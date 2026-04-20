-- PayChangu subscription payments + webhook support.
-- Stores gateway events and allows backend to update user_subscriptions.

create extension if not exists pgcrypto;
create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'paychangu',
  provider_reference text not null,
  event_type text,
  status text not null default 'pending' check (status in ('pending','paid','failed','cancelled','refunded','unknown')),

  user_id text,
  plan_id text references public.subscription_plans (plan_id) on delete set null,
  user_subscription_id bigint references public.user_subscriptions (id) on delete set null,

  amount_mwk numeric(14,2) not null default 0,
  currency text,
  country_code text,

  raw jsonb not null default '{}'::jsonb,
  meta jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint subscription_payments_provider_ref_unique unique (provider, provider_reference)
);
create index if not exists subscription_payments_created_at_idx on public.subscription_payments (created_at desc);
create index if not exists subscription_payments_user_idx on public.subscription_payments (user_id, created_at desc);
create index if not exists subscription_payments_plan_idx on public.subscription_payments (plan_id, created_at desc);
alter table public.subscription_payments enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'subscription_payments'
      and policyname = 'deny_all_subscription_payments'
  ) then
    create policy deny_all_subscription_payments
      on public.subscription_payments
      for all
      using (false)
      with check (false);
  end if;
end $$;
