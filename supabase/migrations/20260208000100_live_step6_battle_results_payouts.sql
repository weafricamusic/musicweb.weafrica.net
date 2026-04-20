-- STEP 6 — Battle end → results → payouts (server-side, atomic)
--
-- Goals:
-- - Battle gifts contribute to a battle "pot" (no immediate creator credit)
-- - Backend finalizes winner + payouts when the timer hits 0
-- - Wallet updates are atomic (single DB transaction)
-- - Store final result + top gifters for the Result Screen

-- 1) Extend battle + gift event schemas

alter table public.live_gift_events
  add column if not exists battle_id text;

create index if not exists live_gift_events_battle_created_at_idx
  on public.live_gift_events (battle_id, created_at desc);

alter table public.live_battles
  add column if not exists host_a_score bigint,
  add column if not exists host_b_score bigint,
  add column if not exists host_a_payout_coins bigint,
  add column if not exists host_b_payout_coins bigint,
  add column if not exists winner_uid text,
  add column if not exists is_draw boolean not null default false,
  add column if not exists total_spent_coins bigint,
  add column if not exists platform_fee_coins bigint,
  add column if not exists winner_payout_coins bigint,
  add column if not exists loser_payout_coins bigint,
  add column if not exists finalized_at timestamptz,
  add column if not exists top_gifters jsonb;

-- 2) Creator stats (simple & extensible)

create table if not exists public.creator_stats (
  creator_id text primary key,
  total_battles bigint not null default 0,
  wins bigint not null default 0,
  total_coins_earned bigint not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.creator_stats enable row level security;

do $$
begin
  create policy "Public read creator_stats" on public.creator_stats
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

grant select on table public.creator_stats to anon, authenticated;

-- 3) Battle gift RPC (deduct viewer coins, log event, NO immediate creator credit)

create or replace function public.battle_send_gift(
  p_battle_id text,
  p_live_id text,
  p_channel_id text,
  p_from_user_id text,
  p_to_host_id text,
  p_gift_id text,
  p_coin_cost bigint,
  p_sender_name text
)
returns table (new_balance bigint, event_id uuid)
language plpgsql
as $$
declare
  b public.live_battles;
  now_ts timestamptz := now();
  current_balance bigint;
  normalized_name text;
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required' using errcode = 'P0001';
  end if;
  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  -- Lock battle row.
  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found' using errcode = 'P0001';
  end if;

  if b.status <> 'live' then
    raise exception 'battle_locked' using errcode = 'P0001';
  end if;

  -- Timer is authoritative.
  if b.ends_at is not null and now_ts >= b.ends_at then
    raise exception 'battle_time_elapsed' using errcode = 'P0001';
  end if;

  if not (b.host_a_id = trim(p_to_host_id) or b.host_b_id = trim(p_to_host_id)) then
    raise exception 'invalid_host' using errcode = 'P0001';
  end if;

  -- Viewer wallet row.
  insert into public.wallets(user_id, coin_balance)
  values (p_from_user_id, 0)
  on conflict (user_id) do nothing;

  select coin_balance
    into current_balance
    from public.wallets
    where user_id = p_from_user_id
    for update;

  if current_balance < p_coin_cost then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;

  update public.wallets
    set coin_balance = coin_balance - p_coin_cost,
        updated_at = now_ts
    where user_id = p_from_user_id
    returning coin_balance into new_balance;

  normalized_name := coalesce(nullif(trim(p_sender_name), ''), 'User');

  insert into public.live_gift_events(
    live_id,
    channel_id,
    battle_id,
    from_user_id,
    sender_name,
    to_host_id,
    gift_id,
    coin_cost
  ) values (
    nullif(trim(p_live_id), ''),
    p_channel_id,
    trim(p_battle_id),
    p_from_user_id,
    normalized_name,
    p_to_host_id,
    p_gift_id,
    p_coin_cost
  ) returning id into event_id;

  return next;
end;
$$;

-- 4) Finalize battle (winner + payouts + stats) when due.
--    This function is safe to call multiple times (idempotent).

create or replace function public.battle_finalize_due(
  p_battle_id text
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  now_ts timestamptz := now();

  a_score bigint := 0;
  b_score bigint := 0;
  total bigint := 0;

  -- Percentages (can be tuned later; keep constants server-side)
  platform_pct numeric := 0.30;
  winner_pct numeric := 0.60;
  loser_pct numeric := 0.10;

  platform_coins bigint := 0;
  winner_coins bigint := 0;
  loser_coins bigint := 0;

  creator_a_payout bigint := 0;
  creator_b_payout bigint := 0;

  winner_uid text := null;
  is_draw boolean := false;
  top jsonb := '[]'::jsonb;

  creator_pool bigint := 0;
  half bigint := 0;
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found';
  end if;

  -- Only finalize once.
  if b.finalized_at is not null then
    return b;
  end if;

  -- Only finalize when timer is due.
  if b.status = 'live' and b.ends_at is not null and now_ts < b.ends_at then
    return b;
  end if;

  -- Ensure ended timestamps.
  if b.status <> 'ended' then
    update public.live_battles
      set status = 'ended',
          ends_at = coalesce(ends_at, now_ts),
          ended_at = coalesce(ended_at, now_ts)
    where battle_id = trim(p_battle_id)
    returning * into b;
  else
    update public.live_battles
      set ends_at = coalesce(ends_at, now_ts),
          ended_at = coalesce(ended_at, now_ts)
    where battle_id = trim(p_battle_id)
    returning * into b;
  end if;

  -- Aggregate scores from battle-tagged gift events.
  select
    coalesce(sum(case when e.to_host_id = b.host_a_id then e.coin_cost else 0 end), 0),
    coalesce(sum(case when e.to_host_id = b.host_b_id then e.coin_cost else 0 end), 0)
  into a_score, b_score
  from public.live_gift_events e
  where e.battle_id = b.battle_id
    and (b.started_at is null or e.created_at >= b.started_at)
    and e.created_at <= b.ended_at;

  total := coalesce(a_score, 0) + coalesce(b_score, 0);

  -- Winner logic (simple & solid)
  if a_score > b_score then
    winner_uid := b.host_a_id;
  elsif b_score > a_score then
    winner_uid := b.host_b_id;
  else
    winner_uid := null;
    is_draw := true;
  end if;

  -- Top gifters (top 3)
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', x.from_user_id,
        'sender_name', x.sender_name,
        'coins', x.coins
      )
    ),
    '[]'::jsonb
  )
  into top
  from (
    select
      e.from_user_id,
      max(e.sender_name) as sender_name,
      sum(e.coin_cost) as coins
    from public.live_gift_events e
    where e.battle_id = b.battle_id
      and (b.started_at is null or e.created_at >= b.started_at)
      and e.created_at <= b.ended_at
    group by e.from_user_id
    order by sum(e.coin_cost) desc
    limit 3
  ) x;

  -- Payout math (integer-safe; remainder goes to platform)
  if total > 0 then
    if is_draw then
      creator_pool := floor(total * (winner_pct + loser_pct));
      platform_coins := total - creator_pool;
      half := floor(creator_pool / 2);
      creator_a_payout := half;
      creator_b_payout := creator_pool - half;
    else
      platform_coins := floor(total * platform_pct);
      winner_coins := floor(total * winner_pct);
      loser_coins := floor(total * loser_pct);
      platform_coins := platform_coins + (total - (platform_coins + winner_coins + loser_coins));

      if winner_uid = b.host_a_id then
        creator_a_payout := winner_coins;
        creator_b_payout := loser_coins;
      else
        creator_a_payout := loser_coins;
        creator_b_payout := winner_coins;
      end if;
    end if;
  end if;

  -- Credit creator wallets + platform wallet atomically.
  if b.host_a_id is not null and length(trim(b.host_a_id)) > 0 then
    insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
    values (b.host_a_id, 0, 0)
    on conflict (artist_id) do nothing;

    update public.artist_wallets
      set earned_coins = earned_coins + coalesce(creator_a_payout, 0),
          withdrawable_coins = withdrawable_coins + coalesce(creator_a_payout, 0),
          updated_at = now_ts
    where artist_id = b.host_a_id;
  end if;

  if b.host_b_id is not null and length(trim(b.host_b_id)) > 0 then
    insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
    values (b.host_b_id, 0, 0)
    on conflict (artist_id) do nothing;

    update public.artist_wallets
      set earned_coins = earned_coins + coalesce(creator_b_payout, 0),
          withdrawable_coins = withdrawable_coins + coalesce(creator_b_payout, 0),
          updated_at = now_ts
    where artist_id = b.host_b_id;
  end if;

  -- Platform wallet (stored in artist_wallets for now).
  insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
  values ('platform', 0, 0)
  on conflict (artist_id) do nothing;

  update public.artist_wallets
    set earned_coins = earned_coins + coalesce(platform_coins, 0),
        withdrawable_coins = withdrawable_coins + coalesce(platform_coins, 0),
        updated_at = now_ts
  where artist_id = 'platform';

  -- Creator stats
  if b.host_a_id is not null and length(trim(b.host_a_id)) > 0 then
    insert into public.creator_stats(creator_id, total_battles, wins, total_coins_earned)
    values (b.host_a_id, 0, 0, 0)
    on conflict (creator_id) do nothing;

    update public.creator_stats
      set total_battles = total_battles + 1,
          wins = wins + case when (not is_draw and winner_uid = b.host_a_id) then 1 else 0 end,
          total_coins_earned = total_coins_earned + coalesce(creator_a_payout, 0),
          updated_at = now_ts
    where creator_id = b.host_a_id;
  end if;

  if b.host_b_id is not null and length(trim(b.host_b_id)) > 0 then
    insert into public.creator_stats(creator_id, total_battles, wins, total_coins_earned)
    values (b.host_b_id, 0, 0, 0)
    on conflict (creator_id) do nothing;

    update public.creator_stats
      set total_battles = total_battles + 1,
          wins = wins + case when (not is_draw and winner_uid = b.host_b_id) then 1 else 0 end,
          total_coins_earned = total_coins_earned + coalesce(creator_b_payout, 0),
          updated_at = now_ts
    where creator_id = b.host_b_id;
  end if;

  -- Store final result on battle row.
  update public.live_battles
    set host_a_score = a_score,
        host_b_score = b_score,
        host_a_payout_coins = creator_a_payout,
        host_b_payout_coins = creator_b_payout,
        winner_uid = winner_uid,
        is_draw = is_draw,
        total_spent_coins = total,
        platform_fee_coins = platform_coins,
        winner_payout_coins = winner_coins,
        loser_payout_coins = loser_coins,
        top_gifters = top,
        finalized_at = now_ts
  where battle_id = trim(p_battle_id)
  returning * into b;

  return b;
end;
$$;

-- 5) Replace battle_end to be timer-authoritative (Option A) and finalize payouts.
create or replace function public.battle_end(
  p_battle_id text,
  p_user_id text,
  p_reason text
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  now_ts timestamptz := now();
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found';
  end if;

  if not (b.host_a_id = trim(p_user_id) or b.host_b_id = trim(p_user_id)) then
    raise exception 'not_a_host';
  end if;

  -- Option A: end only when timer is due.
  if b.ends_at is not null and now_ts < b.ends_at then
    raise exception 'battle_not_due';
  end if;

  -- Delegate to due finalizer (idempotent).
  return public.battle_finalize_due(trim(p_battle_id));
end;
$$;

revoke all on function public.battle_send_gift(text, text, text, text, text, text, bigint, text) from public;
revoke all on function public.battle_finalize_due(text) from public;
revoke all on function public.battle_end(text, text, text) from public;

grant execute on function public.battle_send_gift(text, text, text, text, text, text, bigint, text) to service_role;
grant execute on function public.battle_finalize_due(text) to service_role;
grant execute on function public.battle_end(text, text, text) to service_role;
