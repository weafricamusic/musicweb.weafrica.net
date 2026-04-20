-- Ticketing v2 RPCs
--
-- Service-role only. Clients must call via Edge Functions.
--
-- Core flows:
-- - ticketing_create_pending_checkout: reserves inventory, optionally debits coins, may immediately issue tickets (free/coins)
-- - ticketing_finalize_paid_order: webhook finalization for cash/mixed
-- - ticketing_expire_pending_orders: releases reservations + refunds coins
-- - ticketing_checkin_ticket: admin code-entry check-in with full audit logs

create extension if not exists pgcrypto;

-- --------------------
-- Helpers
-- --------------------

create or replace function public.ticketing_now()
returns timestamptz
language sql
stable
as $$
  select now();
$$;

-- --------------------
-- Create pending checkout (consumer)
-- --------------------

create or replace function public.ticketing_create_pending_checkout(
  p_buyer_user_id text,
  p_event_id uuid,
  p_items jsonb,
  p_payment_mode text,
  p_coins_to_apply bigint,
  p_country_code text,
  p_idempotency_key text,
  p_buyer_name text,
  p_buyer_email text,
  p_buyer_phone text
)
returns table (
  order_id uuid,
  mode text,
  currency_code text,
  gross_amount_cents int,
  coins_used bigint,
  coins_value_amount_cents int,
  cash_due_amount_cents int,
  status text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text;
  v_key text;
  v_mode text;
  v_order_id uuid;
  v_existing record;

  v_event record;

  v_ttl_seconds int := 600;
  v_expires_at timestamptz;

  v_currency text := null;
  v_gross int := 0;
  v_total_qty int := 0;

  v_rate record;
  v_coins_to_apply bigint := 0;
  v_coins_used bigint := 0;
  v_coins_value int := 0;
  v_cash_due int := 0;

  v_wallet_balance numeric := 0;

  v_row record;
  v_already_issued int;
  v_pending_qty int;
  v_event_issued int;
  v_event_pending int;
  v_event_max int;

  v_code text;
  i int;
  v_now timestamptz := public.ticketing_now();
  v_status text;
begin
  v_uid := nullif(trim(p_buyer_user_id), '');
  v_key := nullif(trim(p_idempotency_key), '');
  v_mode := lower(nullif(trim(p_payment_mode), ''));

  if v_uid is null then
    raise exception 'missing_buyer_user_id' using errcode = 'P0001';
  end if;

  if v_key is null then
    raise exception 'missing_idempotency_key' using errcode = 'P0001';
  end if;

  if p_event_id is null then
    raise exception 'missing_event_id' using errcode = 'P0001';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'items_required' using errcode = 'P0001';
  end if;

  if v_mode is null or v_mode not in ('free','coins','cash','mixed') then
    raise exception 'invalid_payment_mode' using errcode = 'P0001';
  end if;

  -- Idempotency fast-path.
  select
    o.id,
    o.payment_mode,
    o.currency_code,
    o.total_amount_cents,
    o.coins_used,
    o.coins_value_amount_cents,
    o.cash_due_amount_cents,
    o.status,
    o.expires_at
  into v_existing
  from public.ticketing_ticket_orders o
  where o.buyer_user_id = v_uid
    and o.idempotency_key = v_key
  limit 1;

  if found then
    return query
      select
        (v_existing.id)::uuid,
        coalesce(v_existing.payment_mode, v_mode)::text,
        (v_existing.currency_code)::text,
        (v_existing.total_amount_cents)::int,
        coalesce(v_existing.coins_used, 0)::bigint,
        coalesce(v_existing.coins_value_amount_cents, 0)::int,
        coalesce(v_existing.cash_due_amount_cents, 0)::int,
        (v_existing.status)::text,
        (v_existing.expires_at)::timestamptz;
    return;
  end if;

  -- Load event.
  select * into v_event
  from public.ticketing_events e
  where e.id = p_event_id;

  if not found then
    raise exception 'event_not_found' using errcode = 'P0001';
  end if;

  if coalesce(v_event.status, '') <> 'published' then
    raise exception 'event_not_published' using errcode = 'P0001';
  end if;

  if coalesce(v_event.sales_enabled, true) is not true then
    raise exception 'sales_disabled' using errcode = 'P0001';
  end if;

  if v_event.ends_at is not null and v_now > v_event.ends_at then
    raise exception 'event_ended' using errcode = 'P0001';
  end if;

  -- Resolve reservation TTL (seconds).
  select c.reservation_ttl_seconds into v_ttl_seconds
  from public.ticketing_config c
  where c.id = 1;

  v_ttl_seconds := coalesce(v_ttl_seconds, 600);
  if v_ttl_seconds < 60 then v_ttl_seconds := 60; end if;
  if v_ttl_seconds > 86400 then v_ttl_seconds := 86400; end if;

  v_expires_at := v_now + make_interval(secs => v_ttl_seconds);

  -- Insert the order first to claim the idempotency key under concurrency.
  v_order_id := gen_random_uuid();

  begin
    insert into public.ticketing_ticket_orders (
      id,
      event_id,
      buyer_user_id,
      idempotency_key,
      buyer_name,
      buyer_email,
      buyer_phone,
      status,
      payment_mode,
      total_amount_cents,
      currency_code,
      coins_used,
      coins_value_amount_cents,
      cash_due_amount_cents,
      expires_at
    ) values (
      v_order_id,
      p_event_id,
      v_uid,
      v_key,
      nullif(trim(p_buyer_name), ''),
      nullif(trim(lower(p_buyer_email)), ''),
      nullif(trim(p_buyer_phone), ''),
      'pending',
      v_mode,
      0,
      'USD',
      0,
      0,
      0,
      v_expires_at
    );
  exception when unique_violation then
    -- Another request with the same (buyer_user_id, idempotency_key) already created the order.
    select
      o.id,
      o.payment_mode,
      o.currency_code,
      o.total_amount_cents,
      o.coins_used,
      o.coins_value_amount_cents,
      o.cash_due_amount_cents,
      o.status,
      o.expires_at
    into v_existing
    from public.ticketing_ticket_orders o
    where o.buyer_user_id = v_uid
      and o.idempotency_key = v_key
    limit 1;

    if not found then
      raise;
    end if;

    return query
      select
        (v_existing.id)::uuid,
        coalesce(v_existing.payment_mode, v_mode)::text,
        (v_existing.currency_code)::text,
        (v_existing.total_amount_cents)::int,
        coalesce(v_existing.coins_used, 0)::bigint,
        coalesce(v_existing.coins_value_amount_cents, 0)::int,
        coalesce(v_existing.cash_due_amount_cents, 0)::int,
        (v_existing.status)::text,
        (v_existing.expires_at)::timestamptz;
    return;
  end;

  -- Lock ticket types and reserve inventory.
  for v_row in
    with raw as (
      select *
      from jsonb_to_recordset(p_items) as x(ticket_type_id uuid, quantity int)
    ),
    items as (
      select
        ticket_type_id,
        sum(quantity)::int as quantity
      from raw
      where ticket_type_id is not null
        and quantity is not null
        and quantity > 0
      group by ticket_type_id
    )
    select
      i.ticket_type_id,
      i.quantity as qty,
      tt.id as found_id,
      tt.event_id,
      tt.name,
      tt.price_cents,
      tt.currency_code,
      tt.quantity_total,
      tt.quantity_sold,
      tt.quantity_reserved,
      tt.is_active,
      tt.sales_enabled,
      tt.sales_start_at,
      tt.sales_end_at,
      tt.max_per_user
    from items i
    left join public.ticketing_ticket_types tt
      on tt.id = i.ticket_type_id
    order by i.ticket_type_id
    for update of tt
  loop
    if v_row.found_id is null then
      raise exception 'ticket_type_not_found' using errcode = 'P0001';
    end if;

    if v_row.event_id <> p_event_id then
      raise exception 'ticket_type_event_mismatch' using errcode = 'P0001';
    end if;

    if v_row.qty <= 0 then
      raise exception 'quantity_must_be_positive' using errcode = 'P0001';
    end if;

    if v_row.is_active is not true then
      raise exception 'ticket_type_inactive' using errcode = 'P0001';
    end if;

    if coalesce(v_row.sales_enabled, true) is not true then
      raise exception 'ticket_type_sales_disabled' using errcode = 'P0001';
    end if;

    if v_row.sales_start_at is not null and v_now < v_row.sales_start_at then
      raise exception 'sales_not_started' using errcode = 'P0001';
    end if;

    if v_row.sales_end_at is not null and v_now > v_row.sales_end_at then
      raise exception 'sales_ended' using errcode = 'P0001';
    end if;

    if (v_row.quantity_sold + v_row.quantity_reserved + v_row.qty) > v_row.quantity_total then
      raise exception 'not_enough_inventory' using errcode = 'P0001';
    end if;

    if v_currency is null then
      v_currency := v_row.currency_code;
    elsif v_row.currency_code <> v_currency then
      raise exception 'mixed_currency_not_supported' using errcode = 'P0001';
    end if;

    if v_event.currency_code is not null and v_event.currency_code <> v_currency then
      raise exception 'event_currency_mismatch' using errcode = 'P0001';
    end if;

    -- Per-ticket-type max per user.
    if v_row.max_per_user is not null and v_row.max_per_user > 0 then
      select count(*) into v_already_issued
      from public.ticketing_tickets t
      join public.ticketing_ticket_orders o on o.id = t.order_id
      where o.buyer_user_id = v_uid
        and t.ticket_type_id = v_row.found_id
        and o.status = 'paid'
        and t.status <> 'voided';

      select coalesce(sum(oi.quantity), 0)::int into v_pending_qty
      from public.ticketing_ticket_order_items oi
      join public.ticketing_ticket_orders o on o.id = oi.order_id
      where o.buyer_user_id = v_uid
        and oi.ticket_type_id = v_row.found_id
        and o.status = 'pending'
        and o.expires_at is not null
        and o.expires_at > v_now;

      if (coalesce(v_already_issued, 0) + coalesce(v_pending_qty, 0) + v_row.qty) > v_row.max_per_user then
        raise exception 'max_per_user_exceeded' using errcode = 'P0001';
      end if;
    end if;

    insert into public.ticketing_ticket_order_items (
      order_id,
      ticket_type_id,
      ticket_type_name,
      quantity,
      unit_price_cents,
      line_total_cents
    ) values (
      v_order_id,
      v_row.found_id,
      v_row.name,
      v_row.qty,
      v_row.price_cents,
      v_row.price_cents * v_row.qty
    );

    update public.ticketing_ticket_types
      set quantity_reserved = quantity_reserved + v_row.qty,
          updated_at = now()
      where id = v_row.found_id;

    v_gross := v_gross + (v_row.price_cents * v_row.qty);
    v_total_qty := v_total_qty + v_row.qty;
  end loop;

  if v_total_qty <= 0 then
    raise exception 'items_required' using errcode = 'P0001';
  end if;

  -- Per-event max tickets per user.
  v_event_max := v_event.max_tickets_per_user;
  if v_event_max is not null and v_event_max > 0 then
    select count(*) into v_event_issued
    from public.ticketing_tickets t
    join public.ticketing_ticket_orders o on o.id = t.order_id
    where o.buyer_user_id = v_uid
      and t.event_id = p_event_id
      and o.status = 'paid'
      and t.status <> 'voided';

    select coalesce(sum(oi.quantity), 0)::int into v_event_pending
    from public.ticketing_ticket_order_items oi
    join public.ticketing_ticket_orders o on o.id = oi.order_id
    where o.buyer_user_id = v_uid
      and o.event_id = p_event_id
      and o.status = 'pending'
      and o.expires_at is not null
      and o.expires_at > v_now;

    if (coalesce(v_event_issued, 0) + coalesce(v_event_pending, 0) + v_total_qty) > v_event_max then
      raise exception 'event_max_tickets_per_user_exceeded' using errcode = 'P0001';
    end if;
  end if;

  v_coins_to_apply := greatest(coalesce(p_coins_to_apply, 0), 0);

  if v_gross = 0 then
    v_mode := 'free';
  end if;

  if v_mode in ('coins','mixed') then
    select * into v_rate
    from public.coin_conversion_rates r
    where upper(r.currency_code) = upper(v_currency)
      and r.active = true
    limit 1;

    if not found then
      raise exception 'missing_coin_conversion_rate' using errcode = 'P0001';
    end if;
  end if;

  if v_mode = 'free' then
    if v_gross <> 0 then
      raise exception 'free_requires_zero_amount' using errcode = 'P0001';
    end if;
    v_coins_used := 0;
    v_coins_value := 0;
    v_cash_due := 0;
  elsif v_mode = 'cash' then
    v_coins_used := 0;
    v_coins_value := 0;
    v_cash_due := v_gross;
  elsif v_mode = 'coins' then
    -- coins_used = ceil(gross * denom / numer)
    v_coins_used := ((v_gross::bigint * v_rate.minor_units_per_coin_denom) + (v_rate.minor_units_per_coin_numer - 1)) / v_rate.minor_units_per_coin_numer;
    v_coins_value := v_gross;
    v_cash_due := 0;
  elsif v_mode = 'mixed' then
    -- Clamp applied coins so coin value never exceeds gross.
    v_coins_used := least(
      v_coins_to_apply,
      (v_gross::bigint * v_rate.minor_units_per_coin_denom) / v_rate.minor_units_per_coin_numer
    );

    v_coins_value := ((v_coins_used * v_rate.minor_units_per_coin_numer) / v_rate.minor_units_per_coin_denom)::int;
    v_cash_due := v_gross - v_coins_value;
  else
    raise exception 'invalid_payment_mode' using errcode = 'P0001';
  end if;

  -- Debit coins up-front for coins/mixed to prevent double-spend.
  if v_coins_used > 0 then
    insert into public.wallets(user_id, coin_balance)
    values (v_uid, 0)
    on conflict (user_id) do nothing;

    select w.coin_balance into v_wallet_balance
    from public.wallets w
    where w.user_id = v_uid
    for update;

    if coalesce(v_wallet_balance, 0) < (v_coins_used::numeric) then
      raise exception 'insufficient_coins' using errcode = 'P0001';
    end if;

    update public.wallets
      set coin_balance = coin_balance - v_coins_used,
          updated_at = now()
      where user_id = v_uid;

    insert into public.wallet_transactions (
      user_id,
      type,
      amount,
      balance_type,
      description,
      metadata
    ) values (
      v_uid,
      'ticketing_spend',
      (-1 * v_coins_used)::numeric,
      'coin',
      'Ticket purchase (coins)',
      jsonb_build_object(
        'order_id', v_order_id,
        'event_id', p_event_id,
        'currency_code', v_currency,
        'coins_used', v_coins_used,
        'coins_value_amount_cents', v_coins_value,
        'cash_due_amount_cents', v_cash_due
      )
    );
  end if;

  -- Set final order totals.
  v_status := case when v_cash_due > 0 then 'pending' else 'paid' end;

  update public.ticketing_ticket_orders
    set
      payment_mode = v_mode,
      total_amount_cents = v_gross,
      currency_code = coalesce(v_currency, 'USD'),
      coins_used = v_coins_used,
      coins_value_amount_cents = v_coins_value,
      cash_due_amount_cents = v_cash_due,
      status = v_status,
      expires_at = case when v_status = 'pending' then v_expires_at else null end,
      paid_at = case when v_status = 'paid' then v_now else null end,
      updated_at = now()
    where id = v_order_id;

  -- If no cash due (free/coins), settle immediately: reserved→sold and issue tickets.
  if v_status = 'paid' then
    for v_row in
      select oi.ticket_type_id, oi.quantity
      from public.ticketing_ticket_order_items oi
      where oi.order_id = v_order_id
      order by oi.ticket_type_id
    loop
      update public.ticketing_ticket_types
        set quantity_reserved = quantity_reserved - v_row.quantity,
            quantity_sold = quantity_sold + v_row.quantity,
            updated_at = now()
        where id = v_row.ticket_type_id;

      for i in 1..v_row.quantity loop
        v_code := encode(gen_random_bytes(10), 'hex');
        insert into public.ticketing_tickets (
          event_id,
          ticket_type_id,
          order_id,
          code,
          status,
          issued_at,
          owner_user_id
        ) values (
          p_event_id,
          v_row.ticket_type_id,
          v_order_id,
          v_code,
          'issued',
          v_now,
          v_uid
        );
      end loop;
    end loop;
  end if;

  return query
    select
      v_order_id,
      v_mode,
      coalesce(v_currency, 'USD'),
      v_gross,
      v_coins_used,
      v_coins_value,
      v_cash_due,
      v_status,
      case when v_status = 'pending' then v_expires_at else null end;
end;
$$;

-- Harden + restrict.
alter function public.ticketing_create_pending_checkout(
  text, uuid, jsonb, text, bigint, text, text, text, text, text
) set search_path = public;

-- --------------------
-- Finalize paid order (PayChangu webhook)
-- --------------------

create or replace function public.ticketing_finalize_paid_order(
  p_order_id uuid,
  p_payment_provider text,
  p_payment_reference text,
  p_verified_amount_cents int,
  p_verified_currency_code text,
  p_raw jsonb
)
returns table (
  ok boolean,
  idempotent boolean,
  order_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text;
  v_ref text;
  v_currency text;
  v_verified_currency text;
  v_order record;
  v_item record;
  v_code text;
  i int;
  v_now timestamptz := public.ticketing_now();
  v_expected int;
begin
  if p_order_id is null then
    raise exception 'missing_order_id' using errcode = 'P0001';
  end if;

  v_provider := nullif(trim(p_payment_provider), '');
  v_ref := nullif(trim(p_payment_reference), '');

  if v_provider is null or v_ref is null then
    raise exception 'missing_payment_reference' using errcode = 'P0001';
  end if;

  select * into v_order
  from public.ticketing_ticket_orders o
  where o.id = p_order_id
  for update;

  if not found then
    return query select false, false, p_order_id;
    return;
  end if;

  if v_order.status = 'paid' then
    return query select true, true, v_order.id;
    return;
  end if;

  if v_order.status <> 'pending' then
    return query select false, false, v_order.id;
    return;
  end if;

  v_expected := coalesce(v_order.cash_due_amount_cents, 0);
  if v_expected <= 0 then
    -- No cash was due; treat as already-settled-only.
    return query select false, false, v_order.id;
    return;
  end if;

  v_currency := coalesce(nullif(trim(v_order.currency_code), ''), 'USD');
  v_verified_currency := coalesce(nullif(trim(p_verified_currency_code), ''), v_currency);

  if upper(v_verified_currency) <> upper(v_currency) then
    update public.ticketing_ticket_orders
      set status = 'failed',
          failure_reason = 'currency_mismatch',
          updated_at = now()
      where id = v_order.id;

    return query select false, false, v_order.id;
    return;
  end if;

  if p_verified_amount_cents < v_expected then
    update public.ticketing_ticket_orders
      set status = 'failed',
          failure_reason = 'amount_mismatch',
          updated_at = now()
      where id = v_order.id;

    return query select false, false, v_order.id;
    return;
  end if;

  -- Settle inventory: reserved→sold and issue tickets.
  for v_item in
    select oi.ticket_type_id, oi.quantity
    from public.ticketing_ticket_order_items oi
    where oi.order_id = v_order.id
    order by oi.ticket_type_id
  loop
    update public.ticketing_ticket_types
      set quantity_reserved = quantity_reserved - v_item.quantity,
          quantity_sold = quantity_sold + v_item.quantity,
          updated_at = now()
      where id = v_item.ticket_type_id;

    for i in 1..v_item.quantity loop
      v_code := encode(gen_random_bytes(10), 'hex');
      insert into public.ticketing_tickets (
        event_id,
        ticket_type_id,
        order_id,
        code,
        status,
        issued_at,
        owner_user_id
      ) values (
        v_order.event_id,
        v_item.ticket_type_id,
        v_order.id,
        v_code,
        'issued',
        v_now,
        v_order.buyer_user_id
      );
    end loop;
  end loop;

  update public.ticketing_ticket_orders
    set
      status = 'paid',
      payment_provider = v_provider,
      payment_reference = v_ref,
      paid_at = v_now,
      expires_at = null,
      updated_at = now()
    where id = v_order.id;

  return query select true, false, v_order.id;
end;
$$;

alter function public.ticketing_finalize_paid_order(
  uuid, text, text, int, text, jsonb
) set search_path = public;

-- --------------------
-- Expire pending orders (releases reservations + refunds coins)
-- --------------------

create or replace function public.ticketing_expire_pending_orders(
  p_now timestamptz default now(),
  p_limit int default 200
)
returns table (
  expired_count int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_item record;
  v_expired int := 0;
  v_uid text;
  v_coins bigint;
begin
  for v_order in
    select *
    from public.ticketing_ticket_orders o
    where o.status = 'pending'
      and o.expires_at is not null
      and o.expires_at <= p_now
    order by o.expires_at asc
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  loop
    -- Release reservations.
    for v_item in
      select oi.ticket_type_id, oi.quantity
      from public.ticketing_ticket_order_items oi
      where oi.order_id = v_order.id
      order by oi.ticket_type_id
    loop
      update public.ticketing_ticket_types
        set quantity_reserved = quantity_reserved - v_item.quantity,
            updated_at = now()
        where id = v_item.ticket_type_id;
    end loop;

    -- Refund coins (if any were debited).
    v_uid := nullif(trim(v_order.buyer_user_id), '');
    v_coins := coalesce(v_order.coins_used, 0);

    if v_uid is not null and v_coins > 0 then
      insert into public.wallets(user_id, coin_balance)
      values (v_uid, 0)
      on conflict (user_id) do nothing;

      update public.wallets
        set coin_balance = coin_balance + v_coins,
            updated_at = now()
        where user_id = v_uid;

      insert into public.wallet_transactions (
        user_id,
        type,
        amount,
        balance_type,
        description,
        metadata
      ) values (
        v_uid,
        'ticketing_refund',
        (v_coins)::numeric,
        'coin',
        'Ticket checkout expired (coins refunded)',
        jsonb_build_object(
          'order_id', v_order.id,
          'event_id', v_order.event_id,
          'coins_refunded', v_coins
        )
      );
    end if;

    update public.ticketing_ticket_orders
      set
        status = 'expired',
        expired_at = p_now,
        updated_at = now(),
        failure_reason = coalesce(failure_reason, 'expired')
      where id = v_order.id;

    v_expired := v_expired + 1;
  end loop;

  return query select v_expired;
end;
$$;

alter function public.ticketing_expire_pending_orders(timestamptz, int) set search_path = public;

-- --------------------
-- Check-in (admin)
-- --------------------

create or replace function public.ticketing_checkin_ticket(
  p_event_id uuid,
  p_ticket_code text,
  p_admin_email text,
  p_meta jsonb default '{}'::jsonb
)
returns table (
  ok boolean,
  reason text,
  ticket_id uuid,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_email text;
  v_ticket record;
  v_now timestamptz := public.ticketing_now();
  v_ok boolean := false;
  v_reason text := null;
begin
  if p_event_id is null then
    raise exception 'missing_event_id' using errcode = 'P0001';
  end if;

  v_code := nullif(trim(p_ticket_code), '');
  if v_code is null then
    raise exception 'missing_ticket_code' using errcode = 'P0001';
  end if;

  v_email := nullif(trim(lower(p_admin_email)), '');

  select * into v_ticket
  from public.ticketing_tickets t
  where t.event_id = p_event_id
    and t.code = v_code
  for update;

  if not found then
    v_ok := false;
    v_reason := 'not_found';

    insert into public.ticketing_checkin_logs (
      event_id,
      ticket_code,
      ticket_id,
      admin_email,
      ok,
      reason,
      meta,
      created_at
    ) values (
      p_event_id,
      v_code,
      null,
      v_email,
      v_ok,
      v_reason,
      coalesce(p_meta, '{}'::jsonb),
      v_now
    );

    return query select v_ok, v_reason, null::uuid, null::text;
    return;
  end if;

  if v_ticket.status = 'voided' then
    v_ok := false;
    v_reason := 'voided';
  elsif v_ticket.status = 'checked_in' then
    v_ok := false;
    v_reason := 'already_checked_in';
  else
    update public.ticketing_tickets
      set status = 'checked_in',
          checked_in_at = coalesce(checked_in_at, v_now),
          scanned_by_admin_email = v_email
      where id = v_ticket.id;

    v_ok := true;
    v_reason := 'checked_in';
  end if;

  insert into public.ticketing_checkin_logs (
    event_id,
    ticket_code,
    ticket_id,
    admin_email,
    ok,
    reason,
    meta,
    created_at
  ) values (
    p_event_id,
    v_code,
    v_ticket.id,
    v_email,
    v_ok,
    v_reason,
    coalesce(p_meta, '{}'::jsonb),
    v_now
  );

  return query select v_ok, v_reason, v_ticket.id, (select status from public.ticketing_tickets where id = v_ticket.id);
end;
$$;

alter function public.ticketing_checkin_ticket(uuid, text, text, jsonb) set search_path = public;

-- --------------------
-- Privileges (service-role only)
-- --------------------

do $$
begin
  revoke all on function public.ticketing_create_pending_checkout(
    text, uuid, jsonb, text, bigint, text, text, text, text, text
  ) from public;

  revoke all on function public.ticketing_finalize_paid_order(
    uuid, text, text, int, text, jsonb
  ) from public;

  revoke all on function public.ticketing_expire_pending_orders(
    timestamptz, int
  ) from public;

  revoke all on function public.ticketing_checkin_ticket(
    uuid, text, text, jsonb
  ) from public;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.ticketing_create_pending_checkout(
      text, uuid, jsonb, text, bigint, text, text, text, text, text
    ) to service_role;

    grant execute on function public.ticketing_finalize_paid_order(
      uuid, text, text, int, text, jsonb
    ) to service_role;

    grant execute on function public.ticketing_expire_pending_orders(
      timestamptz, int
    ) to service_role;

    grant execute on function public.ticketing_checkin_ticket(
      uuid, text, text, jsonb
    ) to service_role;
  end if;
end $$;

notify pgrst, 'reload schema';
