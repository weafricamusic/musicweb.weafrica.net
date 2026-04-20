-- Promotions target-plan widening for the launch catalog.

alter table public.promotions
  add column if not exists deep_link text,
  add column if not exists target_plans text[];

update public.promotions
set target_plan = lower(trim(target_plan))
where target_plan is not null;

update public.promotions
set target_plan = 'platinum'
where target_plan = 'vip';

update public.promotions
set target_plans = (
  select array_agg(distinct v)
  from unnest(coalesce(target_plans, '{}'::text[])) as t(v)
)
where target_plans is not null;

alter table public.promotions
  drop constraint if exists promotions_target_plan_check;

alter table public.promotions
  alter column target_plan set default 'all';

alter table public.promotions
  alter column target_plan set not null;

alter table public.promotions
  add constraint promotions_target_plan_check
  check (length(trim(target_plan)) > 0);

create index if not exists promotions_target_plan_idx
  on public.promotions (target_plan);

create index if not exists promotions_target_plans_gin_idx
  on public.promotions using gin (target_plans);

notify pgrst, 'reload schema';
