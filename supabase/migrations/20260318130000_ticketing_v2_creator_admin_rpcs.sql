-- Ticketing v2 creator/admin RPCs
--
-- Adds:
-- - ticketing_creator_create_event: creator event creation (optional initial ticket type)
-- - ticketing_admin_refund_order: voids tickets + refunds coins + logs refund
-- - ticketing_recompute_payouts: computes per-event payout item inside a batch (global platform cut)
--
-- All functions are SECURITY DEFINER and executable only by service_role.

create extension if not exists pgcrypto;

-- --------------------
-- Creator: Create event (+ optional single ticket type)
-- --------------------

create or replace function public.ticketing_creator_create_event(
  p_host_user_id text,
  p_host_role text,
  p_title text,
  p_starts_at timestamptz,
  p_description text default null,
  p_kind text default 'event',
  p_ends_at timestamptz default null,
  p_country_code text default null,
  p_currency_code text default null,
  p_ticketed boolean default false,
  p_ticket_name text default 'General Admission',
  p_ticket_price_cents int default 0,
  p_ticket_quantity_total int default 0,
  p_max_tickets_per_user int default null
)
returns table (
  event_id uuid,
  ticket_type_id uuid,
  currency_code text,
  access_channel_id text,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text;
  v_role text;
  v_title text;
  v_desc text;
  v_kind text;
  v_country text;
  v_currency text;
  v_is_online boolean := false;
  v_access text := null;

  v_event_id uuid := gen_random_uuid();
  v_tt_id uuid := null;

  v_now timestamptz := public.ticketing_now();
  v_ticket_name text;
  v_ticket_price int;
  v_ticket_qty int;
begin
  v_uid := nullif(trim(p_host_user_id), '');
  if v_uid is null then
    raise exception 'missing_host_user_id' using errcode = 'P0001';
  end if;

  v_title := nullif(trim(p_title), '');
  if v_title is null then
    raise exception 'missing_title' using errcode = 'P0001';
  end if;

  if p_starts_at is null then
    raise exception 'missing_starts_at' using errcode = 'P0001';
  end if;

  v_role := nullif(trim(lower(p_host_role)), '');
  if v_role is null then
    v_role := 'artist';
  end if;

  v_desc := nullif(trim(p_description), '');

  v_kind := nullif(trim(lower(p_kind)), '');
  if v_kind = 'live' then
    v_is_online := true;
  end if;

  v_country := nullif(trim(upper(p_country_code)), '');
  v_currency := nullif(trim(upper(p_currency_code)), '');
  if v_currency is null then
    if v_country = 'MW' then
      v_currency := 'MWK';
    elsif v_country = 'ZA' then
      v_currency := 'ZAR';
    else
      v_currency := 'USD';
    end if;
  end if;

  if v_is_online then
    v_access := 'weafrica_ticketed_event_' || v_event_id::text;
  end if;

  insert into public.ticketing_events (
    id,
    title,
    description,
    cover_image_url,
    venue_name,
    venue_address,
    city,
    country_code,
    starts_at,
    ends_at,
    timezone,
    status,
    created_by_admin_email,
    created_at,
    updated_at,
    host_user_id,
    host_role,
    is_online,
    access_channel_id,
    currency_code,
    sales_enabled,
    max_tickets_per_user,
    published_at
  ) values (
    v_event_id,
    v_title,
    v_desc,
    '',
    null,
    null,
    null,
    v_country,
    p_starts_at,
    p_ends_at,
    'UTC',
    'published',
    null,
    v_now,
    v_now,
    v_uid,
    v_role,
    v_is_online,
    v_access,
    v_currency,
    true,
    p_max_tickets_per_user,
    v_now
  );

  if coalesce(p_ticketed, false) is true then
    v_ticket_name := coalesce(nullif(trim(p_ticket_name), ''), 'General Admission');
    v_ticket_price := coalesce(p_ticket_price_cents, 0);
    v_ticket_qty := coalesce(p_ticket_quantity_total, 0);

    if v_ticket_price < 0 then
      raise exception 'invalid_ticket_price' using errcode = 'P0001';
    end if;

    if v_ticket_qty <= 0 then
      raise exception 'ticket_quantity_total_required' using errcode = 'P0001';
    end if;

    v_tt_id := gen_random_uuid();

    insert into public.ticketing_ticket_types (
      id,
      event_id,
      name,
      description,
      price_cents,
      currency_code,
      quantity_total,
      quantity_sold,
      quantity_reserved,
      sales_start_at,
      sales_end_at,
      is_active,
      sales_enabled,
      max_per_user,
      created_at,
      updated_at
    ) values (
      v_tt_id,
      v_event_id,
      v_ticket_name,
      null,
      v_ticket_price,
      v_currency,
      v_ticket_qty,
      0,
      0,
      v_now,
      p_ends_at,
      true,
      true,
      null,
      v_now,
      v_now
    );
  end if;

  return query
    select v_event_id, v_tt_id, v_currency, v_access, 'published'::text;
end;
$$;

alter function public.ticketing_creator_create_event(
  text, text, text, timestamptz, text, text, timestamptz, text, text, boolean, text, int, int, int
) set search_path = public;

-- --------------------
-- Admin: Refund order (void tickets + refund coins)
-- --------------------

create unique index if not exists ticketing_refunds_order_id_uniq
  on public.ticketing_refunds (order_id);

create or replace function public.ticketing_admin_refund_order(
  p_order_id uuid,
  p_admin_email text,
  p_reason text default null,
  p_meta jsonb default '{}'::jsonb
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
  v_email text := nullif(trim(lower(p_admin_email)), '');
  v_reason text := nullif(trim(p_reason), '');
  v_order record;
  v_item record;
  v_now timestamptz := public.ticketing_now();
  v_currency text;
  v_refund_amount int;
begin
  if p_order_id is null then
    raise exception 'missing_order_id' using errcode = 'P0001';
  end if;

  select * into v_order
  from public.ticketing_ticket_orders o
  where o.id = p_order_id
  for update;

  if not found then
    return query select false, false, p_order_id;
    return;
  end if;

  if v_order.status = 'refunded' then
    return query select true, true, v_order.id;
    return;
  end if;

  if v_order.status <> 'paid' then
    raise exception 'order_not_paid' using errcode = 'P0001';
  end if;

  -- Refund log idempotency: if a refund row exists, do not double-credit.
  if exists (select 1 from public.ticketing_refunds r where r.order_id = v_order.id) then
    return query select true, true, v_order.id;
    return;
  end if;

  v_currency := coalesce(nullif(trim(v_order.currency_code), ''), 'USD');
  v_refund_amount := coalesce(v_order.total_amount_cents, 0);
  if v_refund_amount < 0 then v_refund_amount := 0; end if;

  -- Restore coins (coins/mixed).
  if coalesce(v_order.coins_used, 0) > 0 then
    insert into public.wallets(user_id, coin_balance)
    values (v_order.buyer_user_id, 0)
    on conflict (user_id) do nothing;

    update public.wallets
      set coin_balance = coin_balance + v_order.coins_used,
          updated_at = now()
      where user_id = v_order.buyer_user_id;

    insert into public.wallet_transactions (
      user_id,
      type,
      amount,
      balance_type,
      description,
      metadata
    ) values (
      v_order.buyer_user_id,
      'ticketing_refund',
      (v_order.coins_used)::numeric,
      'coin',
      'Ticket refund (coins)',
      jsonb_build_object(
        'order_id', v_order.id,
        'event_id', v_order.event_id,
        'currency_code', v_currency,
        'coins_refunded', v_order.coins_used
      )
    );
  end if;

  -- Return inventory to allow resale.
  for v_item in
    select oi.ticket_type_id, oi.quantity
    from public.ticketing_ticket_order_items oi
    where oi.order_id = v_order.id
  loop
    update public.ticketing_ticket_types
      set quantity_sold = greatest(quantity_sold - v_item.quantity, 0),
          updated_at = now()
      where id = v_item.ticket_type_id;
  end loop;

  -- Void tickets.
  update public.ticketing_tickets
    set status = 'voided',
        voided_at = coalesce(voided_at, v_now)
    where order_id = v_order.id
      and status <> 'voided';

  -- Mark order refunded.
  update public.ticketing_ticket_orders
    set status = 'refunded',
        refunded_at = v_now,
        updated_at = now()
    where id = v_order.id;

  insert into public.ticketing_refunds (
    order_id,
    provider,
    provider_ref,
    status,
    amount_cents,
    currency_code,
    requested_by_admin_email,
    reason,
    raw,
    created_at
  ) values (
    v_order.id,
    v_order.payment_provider,
    v_order.payment_reference,
    'requested',
    v_refund_amount,
    v_currency,
    v_email,
    v_reason,
    coalesce(p_meta, '{}'::jsonb),
    v_now
  );

  return query select true, false, v_order.id;
end;
$$;

alter function public.ticketing_admin_refund_order(uuid, text, text, jsonb) set search_path = public;

-- --------------------
-- Admin: Recompute payouts (single event into a batch)
-- --------------------

create unique index if not exists ticketing_payout_items_batch_event_uniq
  on public.ticketing_payout_items (batch_id, event_id);

create or replace function public.ticketing_recompute_payouts(
  p_event_id uuid,
  p_batch_id uuid default null,
  p_admin_email text default null,
  p_meta jsonb default '{}'::jsonb
)
returns table (
  batch_id uuid,
  item_id uuid,
  event_id uuid,
  host_user_id text,
  currency_code text,
  gross_amount_cents int,
  refunds_amount_cents int,
  platform_fee_amount_cents int,
  net_amount_cents int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event record;
  v_batch_id uuid;
  v_item_id uuid;
  v_currency text;
  v_gross int := 0;
  v_refunds int := 0;
  v_cut_bps int := 1500;
  v_base int := 0;
  v_fee int := 0;
  v_net int := 0;
  v_now timestamptz := public.ticketing_now();
begin
  if p_event_id is null then
    raise exception 'missing_event_id' using errcode = 'P0001';
  end if;

  select * into v_event
  from public.ticketing_events e
  where e.id = p_event_id;

  if not found then
    raise exception 'event_not_found' using errcode = 'P0001';
  end if;

  v_currency := coalesce(nullif(trim(v_event.currency_code), ''), 'USD');

  if p_batch_id is not null then
    v_batch_id := p_batch_id;

    if not exists (select 1 from public.ticketing_payout_batches b where b.id = v_batch_id) then
      raise exception 'batch_not_found' using errcode = 'P0001';
    end if;

    if exists (select 1 from public.ticketing_payout_batches b where b.id = v_batch_id and b.status <> 'draft') then
      raise exception 'batch_not_draft' using errcode = 'P0001';
    end if;
  else
    insert into public.ticketing_payout_batches (
      status,
      created_by_admin_email,
      meta,
      created_at,
      updated_at
    ) values (
      'draft',
      nullif(trim(lower(p_admin_email)), ''),
      coalesce(p_meta, '{}'::jsonb),
      v_now,
      v_now
    )
    returning id into v_batch_id;
  end if;

  select coalesce(c.platform_cut_bps, 1500) into v_cut_bps
  from public.ticketing_config c
  where c.id = 1;

  -- Gross: sum of paid orders.
  select coalesce(sum(o.total_amount_cents), 0)::int into v_gross
  from public.ticketing_ticket_orders o
  where o.event_id = p_event_id
    and o.status = 'paid';

  -- Refunds: include any non-failed refund request/success.
  select coalesce(sum(r.amount_cents), 0)::int into v_refunds
  from public.ticketing_refunds r
  join public.ticketing_ticket_orders o on o.id = r.order_id
  where o.event_id = p_event_id
    and r.status <> 'failed'
    and r.status <> 'cancelled';

  v_base := greatest(v_gross - v_refunds, 0);
  v_fee := greatest(((v_base::bigint * v_cut_bps::bigint) / 10000)::int, 0);
  v_net := greatest(v_base - v_fee, 0);

  insert into public.ticketing_payout_items (
    batch_id,
    event_id,
    host_user_id,
    currency_code,
    gross_amount_cents,
    refunds_amount_cents,
    platform_fee_amount_cents,
    net_amount_cents,
    status,
    meta,
    created_at,
    updated_at
  ) values (
    v_batch_id,
    p_event_id,
    v_event.host_user_id,
    v_currency,
    v_gross,
    v_refunds,
    v_fee,
    v_net,
    'pending',
    '{}'::jsonb,
    v_now,
    v_now
  )
  on conflict (batch_id, event_id) do update
    set host_user_id = excluded.host_user_id,
        currency_code = excluded.currency_code,
        gross_amount_cents = excluded.gross_amount_cents,
        refunds_amount_cents = excluded.refunds_amount_cents,
        platform_fee_amount_cents = excluded.platform_fee_amount_cents,
        net_amount_cents = excluded.net_amount_cents,
        updated_at = now()
  returning id into v_item_id;

  return query
    select v_batch_id, v_item_id, p_event_id, v_event.host_user_id, v_currency, v_gross, v_refunds, v_fee, v_net;
end;
$$;

alter function public.ticketing_recompute_payouts(uuid, uuid, text, jsonb) set search_path = public;

-- --------------------
-- Privileges (service-role only)
-- --------------------

do $$
begin
  revoke all on function public.ticketing_creator_create_event(
    text, text, text, timestamptz, text, text, timestamptz, text, text, boolean, text, int, int, int
  ) from public;

  revoke all on function public.ticketing_admin_refund_order(uuid, text, text, jsonb) from public;
  revoke all on function public.ticketing_recompute_payouts(uuid, uuid, text, jsonb) from public;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.ticketing_creator_create_event(
      text, text, text, timestamptz, text, text, timestamptz, text, text, boolean, text, int, int, int
    ) to service_role;

    grant execute on function public.ticketing_admin_refund_order(uuid, text, text, jsonb) to service_role;
    grant execute on function public.ticketing_recompute_payouts(uuid, uuid, text, jsonb) to service_role;
  end if;
end $$;

notify pgrst, 'reload schema';
