-- Adds trial support to subscriptions.
-- Trial is not a separate plan; it temporarily grants Pro access.

alter table if exists public.subscriptions
  add column if not exists on_trial boolean not null default false;
alter table if exists public.subscriptions
  add column if not exists trial_started_at timestamptz;
alter table if exists public.subscriptions
  add column if not exists trial_ends_at timestamptz;
-- Helpful for lookups.
create index if not exists idx_subscriptions_user_role on public.subscriptions(user_id, role);
