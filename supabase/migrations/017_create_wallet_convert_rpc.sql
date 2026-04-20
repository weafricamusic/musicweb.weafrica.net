-- Atomic coin->cash conversion: updates wallet balances + logs transaction

create extension if not exists pgcrypto;
create or replace function public.convert_coins_to_cash(
  p_user_id text,
  p_coins numeric,
  p_conversion_rate numeric default 1000
)
returns table (
  new_coin_balance numeric,
  new_cash_balance numeric,
  cash_received numeric
)
language plpgsql
security definer
as $$
declare
  v_coin_balance numeric;
  v_cash_balance numeric;
begin
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id is required';
  end if;

  if p_coins is null or p_coins <= 0 then
    raise exception 'coins must be > 0';
  end if;

  -- Match UI copy: minimum conversion 100 coins
  if p_coins < 100 then
    raise exception 'minimum conversion is 100 coins';
  end if;

  if p_conversion_rate is null or p_conversion_rate <= 0 then
    raise exception 'conversion_rate must be > 0';
  end if;

  -- Ensure wallet exists.
  insert into public.wallets (user_id, coin_balance, cash_balance, total_earned, created_at, updated_at)
  values (p_user_id, 100, 0, 0, now(), now())
  on conflict (user_id) do nothing;

  -- Lock wallet row to prevent races.
  select coin_balance, cash_balance
    into v_coin_balance, v_cash_balance
  from public.wallets
  where user_id = p_user_id
  for update;

  if v_coin_balance < p_coins then
    raise exception 'insufficient coin balance';
  end if;

  cash_received := p_coins / p_conversion_rate;

  update public.wallets
  set coin_balance = coin_balance - p_coins,
      cash_balance = cash_balance + cash_received,
      updated_at = now()
  where user_id = p_user_id
  returning coin_balance, cash_balance
    into new_coin_balance, new_cash_balance;

  insert into public.wallet_transactions (
    user_id,
    type,
    amount,
    balance_type,
    description,
    metadata,
    created_at
  )
  values (
    p_user_id,
    'conversion',
    p_coins,
    'coin',
    'Converted coins to cash',
    jsonb_build_object(
      'conversion_rate', p_conversion_rate,
      'cash_received', cash_received,
      'coins_before', v_coin_balance,
      'coins_after', new_coin_balance,
      'cash_before', v_cash_balance,
      'cash_after', new_cash_balance,
      'source', 'convert_coins_to_cash'
    ),
    now()
  );

  return;
end;
$$;
grant execute on function public.convert_coins_to_cash(text, numeric, numeric) to anon, authenticated;
