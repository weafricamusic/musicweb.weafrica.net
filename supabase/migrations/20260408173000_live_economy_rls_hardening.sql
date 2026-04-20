-- Live economy RLS hardening
--
-- Goals:
-- - Keep live gift/reward reads working for UI.
-- - Prevent client-side wallet mutation (coins are server-controlled).
-- - Ensure reward/gift RPCs cannot be called for another user id.
-- - Keep server/Edge Function flows working via service_role.

-- 1) Wallet lock-down (fan wallet equivalent)
DO $$
BEGIN
  IF to_regclass('public.wallets') IS NOT NULL THEN
    ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS mvp_public_all ON public.wallets;
    DROP POLICY IF EXISTS wallets_insert_own ON public.wallets;
    DROP POLICY IF EXISTS wallets_update_own ON public.wallets;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'wallets'
        AND policyname = 'wallets_select_own'
    ) THEN
      CREATE POLICY wallets_select_own
        ON public.wallets
        FOR SELECT
        TO authenticated
        USING (auth.uid()::text = user_id);
    END IF;

    REVOKE INSERT, UPDATE, DELETE ON TABLE public.wallets FROM anon, authenticated;
    GRANT SELECT ON TABLE public.wallets TO authenticated;
    GRANT ALL ON TABLE public.wallets TO service_role;
  END IF;
END $$;

-- 2) Keep gift events readable for viewers, writes server-side only.
DO $$
BEGIN
  IF to_regclass('public.live_gift_events') IS NOT NULL THEN
    ALTER TABLE public.live_gift_events ENABLE ROW LEVEL SECURITY;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'live_gift_events'
        AND policyname = 'Public read live gifts'
    ) THEN
      CREATE POLICY "Public read live gifts"
        ON public.live_gift_events
        FOR SELECT
        TO anon, authenticated
        USING (true);
    END IF;

    REVOKE INSERT, UPDATE, DELETE ON TABLE public.live_gift_events FROM anon, authenticated;
    GRANT SELECT ON TABLE public.live_gift_events TO anon, authenticated;
    GRANT ALL ON TABLE public.live_gift_events TO service_role;
  END IF;
END $$;

-- 3) Ensure battle requests are self-authored only (defense-in-depth).
DO $$
BEGIN
  IF to_regclass('public.battle_requests') IS NOT NULL THEN
    ALTER TABLE public.battle_requests ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "Users can create requests" ON public.battle_requests;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'battle_requests'
        AND policyname = 'battle_requests_insert_requester'
    ) THEN
      CREATE POLICY battle_requests_insert_requester
        ON public.battle_requests
        FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid()::text = requester_id);
    END IF;
  END IF;
END $$;

-- 4) Harden reward claim RPC identity check.
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
  jwt_sub text := coalesce(auth.jwt() ->> 'sub', '');
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if p_user_id is null or trim(p_user_id) = '' then
    raise exception 'missing_user_id' using errcode = 'P0001';
  end if;
  if p_reward_id is null or trim(p_reward_id) = '' then
    raise exception 'missing_reward_id' using errcode = 'P0001';
  end if;

  -- authenticated callers can only claim for themselves.
  if jwt_role = 'authenticated' and jwt_sub <> trim(p_user_id) then
    raise exception 'forbidden_user_mismatch' using errcode = 'P0001';
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

-- 5) Harden send_gift RPC identity and keep it server-executable.
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
security definer
set search_path = public
as $$
declare
  current_balance bigint;
  normalized_name text;
  new_artist_earned bigint;
  creator_coins bigint;
  platform_coins bigint;
  now_ts timestamptz := now();
  jwt_sub text := coalesce(auth.jwt() ->> 'sub', '');
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if p_from_user_id is null or trim(p_from_user_id) = '' then
    raise exception 'missing_from_user_id' using errcode = 'P0001';
  end if;
  if p_to_host_id is null or trim(p_to_host_id) = '' then
    raise exception 'missing_to_host_id' using errcode = 'P0001';
  end if;
  if p_channel_id is null or trim(p_channel_id) = '' then
    raise exception 'missing_channel_id' using errcode = 'P0001';
  end if;
  if p_gift_id is null or trim(p_gift_id) = '' then
    raise exception 'missing_gift_id' using errcode = 'P0001';
  end if;

  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  -- authenticated callers can only spend from their own wallet.
  if jwt_role = 'authenticated' and jwt_sub <> trim(p_from_user_id) then
    raise exception 'forbidden_sender_mismatch' using errcode = 'P0001';
  end if;

  -- Payout math (integer-safe; remainder to platform)
  creator_coins := (p_coin_cost * 70) / 100;
  platform_coins := p_coin_cost - creator_coins;

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

  insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
  values (p_to_host_id, 0, 0)
  on conflict (artist_id) do nothing;

  update public.artist_wallets
    set earned_coins = earned_coins + creator_coins,
        withdrawable_coins = withdrawable_coins + creator_coins,
        updated_at = now_ts
    where artist_id = p_to_host_id
    returning earned_coins into new_artist_earned;

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
security definer
set search_path = public
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

revoke all on function public.send_gift(text, text, text, text, bigint, text) from public;
revoke all on function public.send_gift(text, text, text, text, text, bigint, text) from public;
grant execute on function public.send_gift(text, text, text, text, bigint, text) to service_role;
grant execute on function public.send_gift(text, text, text, text, text, bigint, text) to service_role;

grant all on table public.artist_wallets to service_role;

notify pgrst, 'reload schema';
