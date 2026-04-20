-- Admin setup additions for subscription configuration UI.

-- 1) Plan active/inactive flag (Free must remain active in UI logic).
alter table public.subscription_plans
  add column if not exists is_active boolean not null default true;
-- Ensure legacy `features` JSON exists for admin editing/export.
alter table public.subscription_plans
  add column if not exists features jsonb not null default '{}'::jsonb;
-- Backfill features JSON (best-effort) so existing deployments get sensible defaults.
update public.subscription_plans
set features = jsonb_strip_nulls(
  jsonb_build_object(
    'ads_enabled', ads_enabled,
    'live_battles', can_participate_battles,
    'live_battle_access', can_participate_battles,
    'priority_live_battle', (battle_priority = 'priority'),
    'coins_multiplier', coins_multiplier,
    'premium_content', (content_access <> 'limited'),
    'analytics_level', analytics_level,
    'featured_status', featured_status
  )
)
where (features is null or features = '{}'::jsonb);
-- 2) Content access rules mapping table (flexible JSON rules per plan).
create table if not exists public.subscription_content_access (
  plan_id text primary key references public.subscription_plans (plan_id) on delete cascade,
  rules jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Compatibility: some older schemas may already have this table but missing `plan_id`.
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_content_access'
      and column_name = 'plan_id'
  ) then
    alter table public.subscription_content_access add column plan_id text;
  end if;

  -- Best-effort backfill from common legacy column names.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_content_access'
      and column_name = 'plan'
  ) then
    execute 'update public.subscription_content_access set plan_id = coalesce(plan_id, plan::text) where plan_id is null and plan is not null';
  end if;
end
$$;
alter table public.subscription_content_access
  add column if not exists rules jsonb not null default '{}'::jsonb;
alter table public.subscription_content_access
  add column if not exists created_at timestamptz not null default now();
alter table public.subscription_content_access
  add column if not exists updated_at timestamptz not null default now();
-- De-duplicate (if needed) before adding uniqueness.
with ranked as (
  select
    ctid,
    plan_id,
    row_number() over (
      partition by plan_id
      order by updated_at desc nulls last, created_at desc nulls last
    ) as rn
  from public.subscription_content_access
  where plan_id is not null
)
delete from public.subscription_content_access t
using ranked r
where t.ctid = r.ctid
  and r.rn > 1;
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'subscription_content_access'
      and column_name = 'plan_id'
  ) then
    execute 'create unique index if not exists subscription_content_access_plan_id_unique on public.subscription_content_access (plan_id)';
  end if;
end
$$;
alter table public.subscription_content_access enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'subscription_content_access'
      and policyname = 'deny_all_subscription_content_access'
  ) then
    create policy deny_all_subscription_content_access
      on public.subscription_content_access
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- Seed default rules (idempotent) without relying on ON CONFLICT.
do $$
begin
  begin
    with seed as (
      select * from (
        values
          (
            'free',
            jsonb_build_object(
              'content_limit_ratio', 0.3,
              'allowed_categories', jsonb_build_array('trending'),
              'videos_access', 'limited',
              'songs_access', 'limited',
              'live_streams', jsonb_build_object(
                'can_watch', true,
                'can_go_live', false,
                'can_join_battles', false,
                'priority_battles', false
              )
            )
          ),
          (
            'premium',
            jsonb_build_object(
              'content_limit_ratio', 1.0,
              'allowed_categories', jsonb_build_array('all'),
              'videos_access', 'standard',
              'songs_access', 'standard',
              'live_streams', jsonb_build_object(
                'can_watch', true,
                'can_go_live', false,
                'can_join_battles', true,
                'priority_battles', false
              ),
              'exclusive_content', jsonb_build_object(
                'level', 'standard'
              )
            )
          ),
          (
            'platinum',
            jsonb_build_object(
              'content_limit_ratio', 1.0,
              'allowed_categories', jsonb_build_array('all'),
              'videos_access', 'vip',
              'songs_access', 'vip',
              'live_streams', jsonb_build_object(
                'can_watch', true,
                'can_go_live', false,
                'can_join_battles', true,
                'priority_battles', true
              ),
              'exclusive_content', jsonb_build_object(
                'level', 'vip',
                'featured_artist_dj', true
              )
            )
          )
      ) as s(plan_id, rules)
    )
    insert into public.subscription_content_access (plan_id, rules)
    select s.plan_id, s.rules
    from seed s
    where not exists (
      select 1 from public.subscription_content_access c where c.plan_id = s.plan_id
    );

    update public.subscription_content_access c
    set rules = s.rules,
        updated_at = now()
    from seed s
    where c.plan_id = s.plan_id;
  exception when others then
    raise notice 'Skipping subscription_content_access seed: %', sqlerrm;
  end;
end
$$;
-- 3) Promotions/messages by subscription level (admin-created announcements).
create table if not exists public.subscription_promotions (
  id uuid primary key default gen_random_uuid(),
  target_plan_id text null references public.subscription_plans (plan_id) on delete set null,
  title text,
  body text not null,
  status text not null default 'published' check (status in ('draft','published','archived')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);
create index if not exists subscription_promotions_target_plan_idx on public.subscription_promotions (target_plan_id);
create index if not exists subscription_promotions_created_at_idx on public.subscription_promotions (created_at desc);
alter table public.subscription_promotions enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'subscription_promotions'
      and policyname = 'deny_all_subscription_promotions'
  ) then
    create policy deny_all_subscription_promotions
      on public.subscription_promotions
      for all
      using (false)
      with check (false);
  end if;
end $$;
