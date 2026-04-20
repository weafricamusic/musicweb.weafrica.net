-- Allow multiple plan tiers per role (consumer/artist/dj) and remove the hardcoded
-- plan_id list constraint so new tiers can be created from the admin UI.

-- 1) Remove the original plan_id whitelist constraint.
-- (Created in 20260114120000_subscriptions_core.sql)
alter table public.subscription_plans
  drop constraint if exists subscription_plans_plan_id_check;
-- 2) Add an optional audience column for filtering/grouping in admin UI.
alter table public.subscription_plans
  add column if not exists audience text;
alter table public.subscription_plans
  drop constraint if exists subscription_plans_audience_check;
alter table public.subscription_plans
  add constraint subscription_plans_audience_check
  check (audience is null or audience in ('consumer','artist','dj'));
update public.subscription_plans
set audience = 'consumer'
where audience is null;
create index if not exists subscription_plans_audience_idx
  on public.subscription_plans (audience);
