-- LIVE SONG REQUESTS (atomic coin spend + chat message)
--
-- This RPC is invoked by the Edge API (service_role) to ensure song requests:
-- - deduct viewer coins atomically (prevents double-spend)
-- - create a chat message in public.live_messages (so the request appears even if the client drops)
-- - optionally write a wallet_transactions ledger entry (if that table exists)

create or replace function public.live_request_song(
  p_live_id uuid,
  p_channel_id text,
  p_user_id text,
  p_username text,
  p_song text,
  p_coin_cost bigint
)
returns table (
  new_balance bigint,
  message_id uuid,
  wallet_transaction_id uuid
)
language plpgsql
as $$
declare
  current_balance bigint;
  now_ts timestamptz := now();
  normalized_name text;
begin
  if p_live_id is null then
    raise exception 'live_id_required' using errcode = 'P0001';
  end if;

  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'invalid_user' using errcode = 'P0001';
  end if;

  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  if p_song is null or length(trim(p_song)) = 0 then
    raise exception 'invalid_song' using errcode = 'P0001';
  end if;

  -- Viewer wallet row.
  insert into public.wallets(user_id, coin_balance)
  values (trim(p_user_id), 0)
  on conflict (user_id) do nothing;

  select coin_balance
    into current_balance
    from public.wallets
    where user_id = trim(p_user_id)
    for update;

  if current_balance < p_coin_cost then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;

  update public.wallets
    set coin_balance = coin_balance - p_coin_cost,
        updated_at = now_ts
    where user_id = trim(p_user_id)
    returning coin_balance into new_balance;

  normalized_name := coalesce(nullif(trim(p_username), ''), 'User');

  insert into public.live_messages (live_id, user_id, username, kind, message, created_at)
  values (
    p_live_id,
    trim(p_user_id),
    normalized_name,
    'message',
    '🎵 Requested: ' || trim(p_song) || ' (' || p_coin_cost::text || ' coins)',
    now_ts
  )
  returning id into message_id;

  if to_regclass('public.wallet_transactions') is not null then
    insert into public.wallet_transactions (
      user_id,
      type,
      amount,
      balance_type,
      description,
      metadata,
      created_at
    ) values (
      trim(p_user_id),
      'debit',
      p_coin_cost,
      'coin',
      'Song request',
      jsonb_build_object(
        'live_id', p_live_id::text,
        'channel_id', nullif(trim(p_channel_id), ''),
        'song', trim(p_song),
        'message_id', message_id::text,
        'source', 'song_request'
      ),
      now_ts
    )
    returning id into wallet_transaction_id;
  else
    wallet_transaction_id := null;
  end if;

  return next;
end;
$$;

revoke all on function public.live_request_song(uuid, text, text, text, text, bigint) from public;
grant execute on function public.live_request_song(uuid, text, text, text, text, bigint) to service_role;

notify pgrst, 'reload schema';
