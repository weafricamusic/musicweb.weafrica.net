-- Phase 1 fan rewards domain.
-- Adds reward configuration, claims, and immutable distribution log.

create extension if not exists pgcrypto;

create table if not exists public.fan_rewards (
  id text primary key,
  name text not null,
  description text,
  trigger_type text not null check (trigger_type in ('gift_total', 'gift_count', 'watch_sessions')),
  trigger_threshold bigint not null check (trigger_threshold > 0),
  reward_type text not null check (reward_type in ('coins', 'badge')),
  reward_value bigint not null check (reward_value >= 0),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fan_reward_claims (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  reward_id text not null references public.fan_rewards(id) on delete cascade,
  claimed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (user_id, reward_id)
);

create table if not exists public.reward_distribution_log (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  reason_code text not null,
  amount_coins numeric not null default 0,
  reference_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists fan_reward_claims_user_claimed_idx
  on public.fan_reward_claims (user_id, claimed_at desc);

create index if not exists reward_distribution_log_user_created_idx
  on public.reward_distribution_log (user_id, created_at desc);

alter table public.fan_rewards enable row level security;
alter table public.fan_reward_claims enable row level security;
alter table public.reward_distribution_log enable row level security;

-- Fan rewards are public read so app can render available milestones.
drop policy if exists "fan_rewards_select_public" on public.fan_rewards;
create policy "fan_rewards_select_public"
  on public.fan_rewards
  for select
  to anon, authenticated
  using (enabled = true);

-- Users can only see their own claims.
drop policy if exists "fan_reward_claims_select_owner" on public.fan_reward_claims;
create policy "fan_reward_claims_select_owner"
  on public.fan_reward_claims
  for select
  to authenticated
  using (user_id = auth.uid()::text);

-- Claims are inserted through RPC only.
drop policy if exists "fan_reward_claims_insert_owner" on public.fan_reward_claims;
create policy "fan_reward_claims_insert_owner"
  on public.fan_reward_claims
  for insert
  to authenticated
  with check (user_id = auth.uid()::text);

-- Distribution log is private to owner row.
drop policy if exists "reward_distribution_log_select_owner" on public.reward_distribution_log;
create policy "reward_distribution_log_select_owner"
  on public.reward_distribution_log
  for select
  to authenticated
  using (user_id = auth.uid()::text);

create or replace function public.claim_fan_reward(
  p_user_id text,
  p_reward_id text
)
returns table (
  ok boolean,
  credited_coins numeric,
  new_balance numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward record;
  v_balance numeric;
  v_credited numeric := 0;
begin
  if p_user_id is null or trim(p_user_id) = '' then
    raise exception 'missing_user_id' using errcode = 'P0001';
  end if;

  select *
    into v_reward
    from public.fan_rewards
    where id = trim(p_reward_id)
      and enabled = true
    limit 1;

  if not found then
    raise exception 'reward_not_found' using errcode = 'P0001';
  end if;

  insert into public.fan_reward_claims (user_id, reward_id)
  values (trim(p_user_id), v_reward.id)
  on conflict (user_id, reward_id) do nothing;

  if not found then
    select coin_balance
      into v_balance
      from public.wallets
      where user_id = trim(p_user_id)
      limit 1;

    return query select true, 0::numeric, coalesce(v_balance, 0);
    return;
  end if;

  if v_reward.reward_type = 'coins' then
    v_credited := coalesce(v_reward.reward_value, 0);

    insert into public.wallets(user_id, coin_balance)
    values (trim(p_user_id), 0)
    on conflict (user_id) do nothing;

    update public.wallets
      set coin_balance = coin_balance + v_credited,
          updated_at = now()
      where user_id = trim(p_user_id)
      returning coin_balance into v_balance;
  else
    select coin_balance
      into v_balance
      from public.wallets
      where user_id = trim(p_user_id)
      limit 1;
  end if;

  insert into public.reward_distribution_log (
    user_id,
    reason_code,
    amount_coins,
    reference_id,
    metadata
  ) values (
    trim(p_user_id),
    'fan_reward_claim',
    v_credited,
    v_reward.id,
    jsonb_build_object('reward_type', v_reward.reward_type, 'reward_name', v_reward.name)
  );

  return query select true, v_credited, coalesce(v_balance, 0);
end;
$$;

revoke all on function public.claim_fan_reward(text, text) from public;

grant execute on function public.claim_fan_reward(text, text) to authenticated, service_role;

insert into public.fan_rewards (id, name, description, trigger_type, trigger_threshold, reward_type, reward_value, enabled)
values
  ('gift-100', 'Gift Starter', 'Send gifts worth 100 coins total', 'gift_total', 100, 'coins', 10, true),
  ('gift-1000', 'Gift Champion', 'Send gifts worth 1000 coins total', 'gift_total', 1000, 'coins', 120, true),
  ('watch-5', 'Loyal Viewer', 'Watch 5 live sessions', 'watch_sessions', 5, 'coins', 20, true)
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  trigger_type = excluded.trigger_type,
  trigger_threshold = excluded.trigger_threshold,
  reward_type = excluded.reward_type,
  reward_value = excluded.reward_value,
  enabled = excluded.enabled,
  updated_at = now();
