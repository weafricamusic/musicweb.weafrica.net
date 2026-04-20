-- STEP 13 — WeAfrica AI Monetization Engine
-- Key idea: free outcomes first, then pay for advantages/scale.
-- - Free daily limits per AI action
-- - Paid usage via (a) earned AI credits, then (b) wallet coins
-- - Performance rewards grant AI credits

-- Pricing: adjustable without redeploying functions.
create table if not exists public.ai_pricing (
  action text primary key,
  coin_cost bigint not null default 0,
  daily_free_limit int not null default 0,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.ai_pricing(action, coin_cost, daily_free_limit, enabled)
values
  ('beat_generation', 50, 3, true),
  ('battle_prediction', 20, 0, true),
  ('advanced_insight', 10, 0, true)
on conflict (action) do update
  set coin_cost = excluded.coin_cost,
      daily_free_limit = excluded.daily_free_limit,
      enabled = excluded.enabled,
      updated_at = now();
-- Daily usage tracking (to enforce free limits and cost control)
create table if not exists public.ai_usage_daily (
  user_id text not null,
  action text not null,
  day date not null,
  free_uses int not null default 0,
  paid_uses int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, action, day)
);
create index if not exists ai_usage_daily_user_day_idx
  on public.ai_usage_daily (user_id, day desc);
-- Earned AI credits (separate from coins) so rewards feel earned, not sold.
create table if not exists public.ai_credit_wallets (
  user_id text primary key,
  credit_balance bigint not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.ai_credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  action text,
  delta bigint not null,
  reason text not null,
  ref_key text,
  meta jsonb,
  created_at timestamptz not null default now()
);
create index if not exists ai_credit_ledger_user_created_at_idx
  on public.ai_credit_ledger (user_id, created_at desc);
-- Prevent duplicate grants/spends per logical reference (e.g., battle_win:<battleId>)
create unique index if not exists ai_credit_ledger_user_ref_key_uniq
  on public.ai_credit_ledger (user_id, ref_key)
  where ref_key is not null;
-- For analytics/auditing: every AI usage that passes through monetization.
create table if not exists public.ai_spend_events (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  action text not null,
  payment_method text not null, -- free|premium|credits|coins
  coin_cost bigint not null default 0,
  credits_cost bigint not null default 0,
  meta jsonb,
  created_at timestamptz not null default now()
);
create index if not exists ai_spend_events_user_created_at_idx
  on public.ai_spend_events (user_id, created_at desc);
-- RLS enabled (service-role via Edge Function remains able to read/write).
alter table public.ai_pricing enable row level security;
alter table public.ai_usage_daily enable row level security;
alter table public.ai_credit_wallets enable row level security;
alter table public.ai_credit_ledger enable row level security;
alter table public.ai_spend_events enable row level security;
-- Record usage (free or paid)
create or replace function public.ai_record_usage(
  p_user_id text,
  p_action text,
  p_day date,
  p_is_free boolean
)
returns table (free_uses int, paid_uses int)
language plpgsql
as $$
begin
  insert into public.ai_usage_daily(user_id, action, day, free_uses, paid_uses)
  values (p_user_id, p_action, p_day, 0, 0)
  on conflict (user_id, action, day) do nothing;

  if p_is_free then
    update public.ai_usage_daily
      set free_uses = free_uses + 1,
          updated_at = now()
      where user_id = p_user_id and action = p_action and day = p_day;
  else
    update public.ai_usage_daily
      set paid_uses = paid_uses + 1,
          updated_at = now()
      where user_id = p_user_id and action = p_action and day = p_day;
  end if;

  return query
    select free_uses, paid_uses
      from public.ai_usage_daily
      where user_id = p_user_id and action = p_action and day = p_day;
end;
$$;
-- Spend earned AI credits atomically.
create or replace function public.ai_spend_credits(
  p_user_id text,
  p_action text,
  p_credits_cost bigint,
  p_ref_key text,
  p_meta jsonb default null
)
returns table (new_credit_balance bigint)
language plpgsql
as $$
declare
  current_balance bigint;
  next_balance bigint;
  inserted boolean;
  ledger_id uuid;
begin
  if p_credits_cost is null or p_credits_cost <= 0 then
    raise exception 'invalid_credits_cost' using errcode = 'P0001';
  end if;

  insert into public.ai_credit_wallets(user_id, credit_balance)
  values (p_user_id, 0)
  on conflict (user_id) do nothing;

  select credit_balance into current_balance
    from public.ai_credit_wallets
    where user_id = p_user_id
    for update;

  if current_balance < p_credits_cost then
    raise exception 'insufficient_ai_credits' using errcode = 'P0001';
  end if;

  next_balance := current_balance - p_credits_cost;

  update public.ai_credit_wallets
    set credit_balance = next_balance,
        updated_at = now()
    where user_id = p_user_id;

  insert into public.ai_credit_ledger(user_id, action, delta, reason, ref_key, meta)
  values (p_user_id, p_action, -p_credits_cost, 'spend', p_ref_key, p_meta)
  returning id into ledger_id;

  new_credit_balance := next_balance;
  return next;
end;
$$;
-- Grant credits once per ref_key to prevent duplicates.
create or replace function public.ai_grant_credits_once(
  p_user_id text,
  p_action text,
  p_credits_amount bigint,
  p_reason text,
  p_ref_key text,
  p_meta jsonb default null
)
returns table (granted boolean, new_credit_balance bigint)
language plpgsql
as $$
declare
  current_balance bigint;
  next_balance bigint;
  exists_row boolean;
begin
  if p_credits_amount is null or p_credits_amount <= 0 then
    raise exception 'invalid_credits_amount' using errcode = 'P0001';
  end if;

  select true into exists_row
    from public.ai_credit_ledger
    where user_id = p_user_id and ref_key = p_ref_key
    limit 1;

  if coalesce(exists_row, false) then
    granted := false;
    insert into public.ai_credit_wallets(user_id, credit_balance)
    values (p_user_id, 0)
    on conflict (user_id) do nothing;

    select credit_balance into new_credit_balance
      from public.ai_credit_wallets
      where user_id = p_user_id;
    return next;
    return;
  end if;

  insert into public.ai_credit_wallets(user_id, credit_balance)
  values (p_user_id, 0)
  on conflict (user_id) do nothing;

  select credit_balance into current_balance
    from public.ai_credit_wallets
    where user_id = p_user_id
    for update;

  next_balance := current_balance + p_credits_amount;

  update public.ai_credit_wallets
    set credit_balance = next_balance,
        updated_at = now()
    where user_id = p_user_id;

  insert into public.ai_credit_ledger(user_id, action, delta, reason, ref_key, meta)
  values (p_user_id, p_action, p_credits_amount, p_reason, p_ref_key, p_meta);

  granted := true;
  new_credit_balance := next_balance;
  return next;
end;
$$;
-- Spend wallet coins atomically for AI.
-- Requires public.wallets from STEP 1.5.
create or replace function public.ai_spend_coins(
  p_user_id text,
  p_action text,
  p_coin_cost bigint,
  p_meta jsonb default null
)
returns table (new_coin_balance bigint)
language plpgsql
as $$
declare
  current_balance bigint;
begin
  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  insert into public.wallets(user_id, coin_balance)
  values (p_user_id, 0)
  on conflict (user_id) do nothing;

  select coin_balance
    into current_balance
    from public.wallets
    where user_id = p_user_id
    for update;

  if current_balance < p_coin_cost then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;

  update public.wallets
    set coin_balance = coin_balance - p_coin_cost,
        updated_at = now()
    where user_id = p_user_id
    returning coin_balance into new_coin_balance;

  insert into public.ai_spend_events(user_id, action, payment_method, coin_cost, credits_cost, meta)
  values (p_user_id, p_action, 'coins', p_coin_cost, 0, p_meta);

  return next;
end;
$$;
