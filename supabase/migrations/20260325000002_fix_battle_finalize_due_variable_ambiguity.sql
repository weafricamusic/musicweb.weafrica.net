-- Fix PL/pgSQL variable/column ambiguity in battle finalization.
--
-- battle_finalize_due() stores result fields like winner_uid and is_draw back
-- onto public.live_battles. In some environments Postgres resolves these as
-- ambiguous column references during UPDATE, causing stream/end to fail.

create or replace function public.battle_finalize_due(
  p_battle_id text
)
returns public.live_battles
language plpgsql
security definer
as $$
#variable_conflict use_variable
declare
  b public.live_battles;
  now_ts timestamptz := now();

  a_score bigint := 0;
  b_score bigint := 0;
  total bigint := 0;

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

  if b.finalized_at is not null then
    return b;
  end if;

  if b.status = 'live' and b.ends_at is not null and now_ts < b.ends_at then
    return b;
  end if;

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

  select
    coalesce(sum(case when e.to_host_id = b.host_a_id then e.coin_cost else 0 end), 0),
    coalesce(sum(case when e.to_host_id = b.host_b_id then e.coin_cost else 0 end), 0)
  into a_score, b_score
  from public.live_gift_events e
  where e.battle_id = b.battle_id
    and (b.started_at is null or e.created_at >= b.started_at)
    and e.created_at <= b.ended_at;

  total := coalesce(a_score, 0) + coalesce(b_score, 0);

  if a_score > b_score then
    winner_uid := b.host_a_id;
  elsif b_score > a_score then
    winner_uid := b.host_b_id;
  else
    winner_uid := null;
    is_draw := true;
  end if;

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

  insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
  values ('platform', 0, 0)
  on conflict (artist_id) do nothing;

  update public.artist_wallets
    set earned_coins = earned_coins + coalesce(platform_coins, 0),
        withdrawable_coins = withdrawable_coins + coalesce(platform_coins, 0),
        updated_at = now_ts
  where artist_id = 'platform';

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

revoke all on function public.battle_finalize_due(text) from public;
grant execute on function public.battle_finalize_due(text) to service_role;