-- Align live gifts catalog + revenue split to the 6-gift launch spec.
--
-- Changes:
-- - Ensure the live_gifts catalog contains the 6 launch gifts with correct costs.
-- - Update send_gift() split to 70% creator / 30% platform (integer-safe).
--
-- NOTE: This is a forward, idempotent migration; it does not rewrite history.

-- 1) Gift catalog (6 launch gifts)
insert into public.live_gifts (id, name, coin_cost, icon_name, enabled, sort_order)
values
  ('fire', 'Fire', 10, 'local_fire_department', true, 10),
  ('love', 'Love', 25, 'favorite', true, 20),
  ('mic_drop', 'Mic Drop', 50, 'mic', true, 30),
  ('star', 'Star', 100, 'star', true, 40),
  ('crown', 'Crown', 250, 'workspace_premium', true, 50),
  ('rocket', 'Rocket', 500, 'rocket_launch', true, 60)
on conflict (id) do update set
  name = excluded.name,
  coin_cost = excluded.coin_cost,
  icon_name = excluded.icon_name,
  enabled = excluded.enabled,
  sort_order = excluded.sort_order,
  updated_at = now();

-- 2) Revenue split for non-battle live gifts
-- Default: 70% creator / 30% platform (integer-safe; remainder goes to platform).
-- Ensure column exists (migration histories can diverge across deployments).
alter table public.live_gift_events
  add column if not exists live_id text;

create or replace function public.send_gift(
  p_live_id text,
  p_channel_id text,
  p_from_user_id text,
  p_to_host_id text,
  p_gift_id text,
  p_coin_cost bigint,
  p_sender_name text
)
returns table (
  new_balance bigint,
  event_id uuid,
  artist_earned_coins bigint
)
language plpgsql
as $$
declare
  current_balance bigint;
  normalized_name text;
  new_artist_earned bigint;
  creator_coins bigint;
  platform_coins bigint;
  now_ts timestamptz := now();
begin
  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  -- Payout math (integer-safe; remainder to platform)
  creator_coins := (p_coin_cost * 70) / 100;
  platform_coins := p_coin_cost - creator_coins;

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

  -- Creator wallet row.
  insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
  values (p_to_host_id, 0, 0)
  on conflict (artist_id) do nothing;

  update public.artist_wallets
    set earned_coins = earned_coins + creator_coins,
        withdrawable_coins = withdrawable_coins + creator_coins,
        updated_at = now_ts
    where artist_id = p_to_host_id
    returning earned_coins into new_artist_earned;

  -- Platform wallet (stored in artist_wallets for now).
  insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
  values ('platform', 0, 0)
  on conflict (artist_id) do nothing;

  update public.artist_wallets
    set earned_coins = earned_coins + platform_coins,
        withdrawable_coins = withdrawable_coins + platform_coins,
        updated_at = now_ts
    where artist_id = 'platform';

  normalized_name := coalesce(nullif(trim(p_sender_name), ''), 'User');

  insert into public.live_gift_events(
    live_id,
    channel_id,
    from_user_id,
    sender_name,
    to_host_id,
    gift_id,
    coin_cost
  ) values (
    nullif(trim(p_live_id), ''),
    p_channel_id,
    p_from_user_id,
    normalized_name,
    p_to_host_id,
    p_gift_id,
    p_coin_cost
  ) returning id into event_id;

  artist_earned_coins := new_artist_earned;
  return next;
end;
$$;

-- Backwards-compatible wrapper for older clients that call the 6-arg version.
-- We treat live_id == channel_id for analytics.
create or replace function public.send_gift(
  p_channel_id text,
  p_from_user_id text,
  p_to_host_id text,
  p_gift_id text,
  p_coin_cost bigint,
  p_sender_name text
)
returns table (
  new_balance bigint,
  event_id uuid
)
language plpgsql
as $$
begin
  return query
  select sg.new_balance, sg.event_id
  from public.send_gift(
    p_channel_id,
    p_channel_id,
    p_from_user_id,
    p_to_host_id,
    p_gift_id,
    p_coin_cost,
    p_sender_name
  ) as sg;
end;
$$;

notify pgrst, 'reload schema';
