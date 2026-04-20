-- Phase 3 wallet ledger support.
--
-- Adds idempotent references to wallet_transactions and an atomic RPC that
-- credits a wallet balance while appending an immutable ledger row.

create extension if not exists pgcrypto;

alter table public.wallet_transactions
  add column if not exists reference text,
  add column if not exists balance_after numeric;

create index if not exists wallet_transactions_reference_idx
  on public.wallet_transactions (reference)
  where reference is not null;

create unique index if not exists wallet_transactions_user_reference_unique
  on public.wallet_transactions (user_id, reference)
  where reference is not null;

create or replace function public.credit_wallet_balance(
  p_user_id text,
  p_amount numeric,
  p_type text,
  p_description text default null,
  p_reference text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_increment_total_earned boolean default true
)
returns table (
  coin_balance numeric,
  total_earned numeric,
  transaction_id uuid
)
language plpgsql
security definer
as $$
declare
  v_existing_tx uuid;
  v_balance numeric;
  v_total_earned numeric;
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  if p_user_id is null or btrim(p_user_id) = '' then
    raise exception 'user_id_required' using errcode = 'P0001';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount_must_be_positive' using errcode = 'P0001';
  end if;

  if p_type is null or btrim(p_type) = '' then
    raise exception 'type_required' using errcode = 'P0001';
  end if;

  insert into public.wallets (user_id, coin_balance, cash_balance, total_earned, created_at, updated_at)
  values (p_user_id, 0, 0, 0, now(), now())
  on conflict (user_id) do nothing;

  if p_reference is not null and btrim(p_reference) <> '' then
    select wt.id
      into v_existing_tx
    from public.wallet_transactions wt
    where wt.user_id = p_user_id
      and wt.reference = btrim(p_reference)
    limit 1;

    if v_existing_tx is not null then
      select w.coin_balance, w.total_earned
        into coin_balance, total_earned
      from public.wallets w
      where w.user_id = p_user_id;

      transaction_id := v_existing_tx;
      return next;
      return;
    end if;
  end if;

  update public.wallets
    set coin_balance = coin_balance + p_amount,
        total_earned = total_earned + case when p_increment_total_earned then p_amount else 0 end,
        updated_at = now()
  where user_id = p_user_id
  returning public.wallets.coin_balance, public.wallets.total_earned
    into v_balance, v_total_earned;

  if p_reference is not null and btrim(p_reference) <> '' then
    v_metadata := v_metadata || jsonb_build_object('reference', btrim(p_reference));
  end if;

  insert into public.wallet_transactions (
    user_id,
    type,
    amount,
    balance_type,
    description,
    metadata,
    reference,
    balance_after,
    created_at
  )
  values (
    p_user_id,
    p_type,
    p_amount,
    'coin',
    nullif(btrim(coalesce(p_description, '')), ''),
    v_metadata,
    nullif(btrim(coalesce(p_reference, '')), ''),
    v_balance,
    now()
  )
  returning id into transaction_id;

  coin_balance := v_balance;
  total_earned := v_total_earned;
  return next;
end;
$$;

revoke all on function public.credit_wallet_balance(text, numeric, text, text, text, jsonb, boolean) from public;
grant execute on function public.credit_wallet_balance(text, numeric, text, text, text, jsonb, boolean) to service_role;

notify pgrst, 'reload schema';