-- Hosted smoke checks for Live Goals + Gift Mapping + Fan Rewards
-- Run in Supabase SQL Editor (hosted project)

-- 1) Migration sync signal (should all be true)
select
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260408140000') as has_live_goals_phase1,
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260408143000') as has_live_goals_trigger,
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260408150000') as has_gift_goal_mapping,
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260408152000') as has_fan_rewards_phase1;

-- 2) Core objects exist
select
  to_regclass('public.live_goals') is not null as live_goals_table_exists,
  to_regclass('public.fan_rewards') is not null as fan_rewards_table_exists,
  to_regclass('public.fan_reward_claims') is not null as fan_reward_claims_table_exists,
  to_regclass('public.reward_distribution_log') is not null as reward_distribution_log_table_exists,
  to_regprocedure('public.claim_fan_reward(text,text)') is not null as claim_fan_reward_rpc_exists;

-- 3) Trigger exists on live_gift_events
select
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'live_gift_events'
      and t.tgname = 'trg_live_goals_apply_gift_event'
      and not t.tgisinternal
  ) as live_goals_trigger_attached;

-- 4) Seed sanity
select id, name, goal_bucket, battle_points, coin_cost
from public.live_gifts
order by sort_order
limit 20;

select id, name, trigger_type, trigger_threshold, reward_type, reward_value, enabled
from public.fan_rewards
order by trigger_threshold asc;

-- 5) RLS policy presence
select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in ('live_goals', 'fan_rewards', 'fan_reward_claims', 'reward_distribution_log')
order by tablename, policyname;
