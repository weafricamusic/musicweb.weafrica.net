-- Atomically spend coins and record a battle gift.
-- Prevents double-spend by locking the wallet row in a single transaction.
-- Identity: Firebase UID stored as TEXT.
--
-- RPC name: public.spend_coins_for_battle_gift(p_user_id text, p_battle_id uuid, p_coins numeric)

create extension if not exists pgcrypto;
create or replace function public.spend_coins_for_battle_gift(
  p_user_id text,
  p_battle_id uuid,
  p_coins numeric
)
returns jsonb
language plpgsql
as $$
declare
  v_balance numeric;
  v_new_balance numeric;
  v_wallet_tx_id uuid;
  v_gift_id uuid;
  v_tx_id uuid;
begin
  if p_user_id is null or btrim(p_user_id) = '' then
    raise exception using message = 'INVALID_USER_ID';
  end if;

  if p_coins is null or p_coins <= 0 then
    raise exception using message = 'INVALID_COINS';
  end if;

  -- Ensure wallet row exists.
  insert into public.wallets (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  -- Lock wallet row.
  select coin_balance
    into v_balance
  from public.wallets
  where user_id = p_user_id
  for update;

  if v_balance is null then
    v_balance := 0;
  end if;

  if v_balance < p_coins then
    raise exception using message = 'INSUFFICIENT_COINS', detail = format('balance=%s, requested=%s', v_balance, p_coins);
  end if;

  v_new_balance := v_balance - p_coins;

  update public.wallets
  set coin_balance = v_new_balance,
      updated_at = now()
  where user_id = p_user_id;

  insert into public.wallet_transactions (
    user_id,
    type,
    amount,
    balance_type,
    description,
    metadata,
    created_at
  ) values (
    p_user_id,
    'debit',
    p_coins,
    'coin',
    'Battle gift',
    jsonb_build_object('battle_id', p_battle_id::text, 'source', 'battle_gift'),
    now()
  ) returning id into v_wallet_tx_id;

  -- Optional: record the gift itself (table exists in this repo's migrations).
  if to_regclass('public.battle_gifts') is not null then
    insert into public.battle_gifts (battle_id, from_user_id, coins, created_at)
    values (p_battle_id, p_user_id, p_coins, now())
    returning id into v_gift_id;
  end if;

  -- Optional: record an entry in a generic transactions table if present in your Supabase.
  if to_regclass('public.transactions') is not null then
    execute $tx$
      insert into public.transactions (user_id, type, amount, description, metadata, created_at)
      values ($1, 'gift', $2, $3, $4, now())
      returning id
    $tx$
    using p_user_id,
          p_coins,
          'Gift for battle ' || p_battle_id::text,
          jsonb_build_object('battle_id', p_battle_id::text)
    into v_tx_id;
  end if;

  perform pg_notify('pgrst', 'reload schema');

  return jsonb_build_object(
    'ok', true,
    'new_balance', v_new_balance,
    'wallet_transaction_id', v_wallet_tx_id,
    'battle_gift_id', v_gift_id,
    'transaction_id', v_tx_id
  );
end;
$$;
grant execute on function public.spend_coins_for_battle_gift(text, uuid, numeric) to anon, authenticated;
-- Ask PostgREST to reload schema cache.
notify pgrst, 'reload schema';
