-- PayChangu payments ledger (used for webhook reconciliation and idempotency)

create table if not exists public.paychangu_payments (
  tx_ref text primary key,
  uid text not null,
  plan_id text not null references public.subscription_plans(plan_id) on update cascade,
  months integer not null default 1,
  amount integer not null default 0,
  currency text not null default 'MWK',
  status text not null default 'pending' check (status in ('pending','success','failed')),
  mode text,
  reference text,
  charge_id text,
  checkout_url text,
  raw jsonb,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists paychangu_payments_uid_idx on public.paychangu_payments(uid);
create index if not exists paychangu_payments_status_idx on public.paychangu_payments(status);
drop trigger if exists set_updated_at_paychangu_payments on public.paychangu_payments;
create trigger set_updated_at_paychangu_payments
before update on public.paychangu_payments
for each row execute function public.set_updated_at();
alter table public.paychangu_payments enable row level security;
