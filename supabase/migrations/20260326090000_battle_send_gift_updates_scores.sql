-- Update battle_send_gift to maintain realtime scores on the battle row.
--
-- Why:
-- - Gift truth remains `live_gift_events` + wallet ledger.
-- - Realtime UI needs an authoritative score snapshot for periodic resync.
-- - Computing scores by summing gift events on every poll does not scale.

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

  -- Maintain realtime scores on the battle row (authoritative snapshot).
  if b.host_a_id = trim(p_to_host_id) then
    update public.live_battles
      set host_a_score = coalesce(host_a_score, 0) + p_coin_cost,
          total_spent_coins = coalesce(total_spent_coins, 0) + p_coin_cost,
          updated_at = now_ts
    where battle_id = b.battle_id;
  else
    update public.live_battles
      set host_b_score = coalesce(host_b_score, 0) + p_coin_cost,
          total_spent_coins = coalesce(total_spent_coins, 0) + p_coin_cost,
          updated_at = now_ts
    where battle_id = b.battle_id;
  end if;

  return next;
end;
$$;
