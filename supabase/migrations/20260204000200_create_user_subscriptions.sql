-- DB-backed user subscriptions for /api/subscriptions/me

create table if not exists public.user_subscriptions (
  uid text primary key,
  plan_id text not null references public.subscription_plans(plan_id) on update cascade,
  status text not null default 'inactive' check (status in ('inactive','active','trialing','canceled','past_due')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  source text,
  metadata jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists user_subscriptions_plan_id_idx on public.user_subscriptions(plan_id);
create index if not exists user_subscriptions_status_idx on public.user_subscriptions(status);
-- Keep updated_at current
-- (set_updated_at() is created in the subscription_plans migration)
drop trigger if exists set_updated_at_user_subscriptions on public.user_subscriptions;
create trigger set_updated_at_user_subscriptions
before update on public.user_subscriptions
for each row execute function public.set_updated_at();
-- Optional: enable RLS (Edge Function uses service role key anyway)
alter table public.user_subscriptions enable row level security;
-- Minimal self-read policy (if you later expose this via Supabase client)
-- Note: This relies on Supabase Auth; your app currently uses Firebase Auth.
-- Keep it permissive only if you plan to use Supabase auth identities.;
