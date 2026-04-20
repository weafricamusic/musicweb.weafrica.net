-- Atomic withdrawal request: inserts request + decrements cash balance + logs transaction

create extension if not exists pgcrypto;
create or replace function public.request_withdrawal(
  p_user_id text,
  p_amount numeric,
  p_payment_method text,
  p_account_details jsonb
)
returns table (
  request_id uuid,
  new_cash_balance numeric
)
language plpgsql
security definer
as $$
declare
  v_cash_balance numeric;
begin
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be > 0';
  end if;

  if p_amount < 10 then
    raise exception 'minimum withdrawal amount is 10';
  end if;

  if p_payment_method is null or length(trim(p_payment_method)) = 0 then
    raise exception 'payment_method is required';
  end if;

  -- Ensure wallet exists.
  insert into public.wallets (user_id, coin_balance, cash_balance, total_earned, created_at, updated_at)
  values (p_user_id, 100, 0, 0, now(), now())
  on conflict (user_id) do nothing;

  -- Lock wallet row to prevent races.
  select cash_balance
    into v_cash_balance
  from public.wallets
  where user_id = p_user_id
  for update;

  if v_cash_balance < p_amount then
    raise exception 'insufficient cash balance';
  end if;

  -- Create withdrawal request.
  insert into public.withdrawal_requests (
    user_id,
    amount,
    status,
    payment_method,
    account_details,
    created_at,
    updated_at
  )
  values (
    p_user_id,
    p_amount,
    'pending',
    p_payment_method,
    coalesce(p_account_details, '{}'::jsonb),
    now(),
    now()
  )
  returning id into request_id;

  -- Decrement cash.
  update public.wallets
  set cash_balance = cash_balance - p_amount,
      updated_at = now()
  where user_id = p_user_id
  returning cash_balance into new_cash_balance;

  -- Log transaction.
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
    'debit',
    p_amount,
    'cash',
    'Withdrawal request',
    jsonb_build_object(
      'request_id', request_id,
      'payment_method', p_payment_method,
      'source', 'withdrawal_request'
    ),
    now()
  );

  return;
end;
$$;
grant execute on function public.request_withdrawal(text, numeric, text, jsonb) to anon, authenticated;
