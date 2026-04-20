-- RPC used by the app to credit coins (Firebase UID stored as TEXT)

create extension if not exists pgcrypto;
create or replace function public.add_coins_to_wallet(
  p_user_id text,
  p_coins numeric
)
returns table (coin_balance numeric, cash_balance numeric)
language plpgsql
security definer
as $$
begin
  -- Ensure wallet exists and increment coin balance atomically.
  insert into public.wallets (user_id, coin_balance, cash_balance, total_earned, created_at, updated_at)
  values (p_user_id, coalesce(p_coins, 0), 0, 0, now(), now())
  on conflict (user_id)
  do update set
    coin_balance = public.wallets.coin_balance + coalesce(excluded.coin_balance, 0),
    updated_at = now()
  returning public.wallets.coin_balance, public.wallets.cash_balance
  into coin_balance, cash_balance;

  return;
end;
$$;
-- Allow calling from the client (MVP dev; tighten for production)
grant execute on function public.add_coins_to_wallet(text, numeric) to anon, authenticated;
