-- LIVE GIFTS: Premium monetization
--
-- 1) Add optional animation_url to the gift catalog.
-- 2) Update send_gift() to split coins between creator + platform.
--
-- Notes:
-- - Identity is Firebase UID (text) throughout this app.
-- - Platform wallet is stored in public.artist_wallets with artist_id = 'platform'.

alter table public.live_gifts
  add column if not exists animation_url text;

-- Revenue split for non-battle live gifts.
-- Default: 80% creator / 20% platform (integer-safe; remainder goes to platform).
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
  creator_pct numeric := 0.80;
  now_ts timestamptz := now();
begin
  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  -- Payout math (integer-safe; remainder to platform)
  creator_coins := floor(p_coin_cost * creator_pct);
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
