-- Create subscriptions table for WeAfrica Music
create table if not exists subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  role text not null, -- consumer | artist | dj
  plan text not null, -- free | premium | pro | elite
  status text not null default 'active', -- active | expired | cancelled
  start_date timestamptz default now(),
  end_date timestamptz,
  payment_provider text,
  metadata jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_subscriptions_user on subscriptions(user_id);
-- Optional: seed default plans into a simple table (optional)
create table if not exists subscription_plans (
  id serial primary key,
  role text not null,
  plan text not null,
  price numeric default 0,
  currency text default 'MWK',
  billing_interval text default 'month',
  features jsonb,
  created_at timestamptz default now()
);
-- Ensure ON CONFLICT (role, plan) is valid
create unique index if not exists idx_subscription_plans_role_plan on subscription_plans(role, plan);
-- Insert basic plans (idempotent)
insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  ('consumer','free',0,'MWK','month', '{"ads":true}'),
  ('consumer','premium',1000,'MWK','month', '{"ads":false,"skips":"unlimited","votes":true}'),
  ('artist','free',0,'MWK','month', '{"uploads":"limited"}'),
  ('artist','pro',2000,'MWK','month', '{"uploads":"unlimited","better_share":true}'),
  ('dj','free',0,'MWK','month', '{"host_battles":false}'),
  ('dj','pro',3000,'MWK','month', '{"host_battles":true}')
on conflict (role, plan) do nothing;
