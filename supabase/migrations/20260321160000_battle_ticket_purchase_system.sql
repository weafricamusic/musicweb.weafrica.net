-- Ticket 3.2 — Battle ticket purchase system (PayChangu)
--
-- Adds:
-- - battle_ticket_purchases: per-user purchase ledger for battle tickets
-- - apply_battle_ticket_purchase_paychangu(): atomic + idempotent finalization on webhook

create extension if not exists pgcrypto;

-- Shared helper for updated_at (safe to re-define).
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.battle_ticket_purchases (
  id uuid primary key default gen_random_uuid(),

  user_id text not null,
  battle_id text not null,
  ticket_id uuid not null,
  tier text not null,

  provider text not null default 'paychangu',
  tx_ref text not null,

  amount numeric not null,
  currency text not null default 'MWK',

  status text not null default 'pending' check (status in ('pending','success','failed')),

  checkout_url text,
  provider_reference text,
  provider_status text,
  verified_at timestamptz,

  raw jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint battle_ticket_purchases_tier_check
    check (tier in ('standard','vip','priority')),
  unique (provider, tx_ref),
  unique (battle_id, user_id)
);

-- Best-effort foreign keys (tolerant if dependencies don't exist yet).
do $$
begin
  if to_regclass('public.live_battles') is not null then
    if not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.battle_ticket_purchases'::regclass
        and conname = 'battle_ticket_purchases_battle_id_fk'
    ) then
      alter table public.battle_ticket_purchases
        add constraint battle_ticket_purchases_battle_id_fk
        foreign key (battle_id)
        references public.live_battles(battle_id)
        on delete cascade;
    end if;
  end if;

  if to_regclass('public.battle_tickets') is not null then
    if not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.battle_ticket_purchases'::regclass
        and conname = 'battle_ticket_purchases_ticket_id_fk'
    ) then
      alter table public.battle_ticket_purchases
        add constraint battle_ticket_purchases_ticket_id_fk
        foreign key (ticket_id)
        references public.battle_tickets(id)
        on delete cascade;
    end if;
  end if;
end $$;

create index if not exists battle_ticket_purchases_battle_id_idx
  on public.battle_ticket_purchases (battle_id);
create index if not exists battle_ticket_purchases_user_id_created_at_idx
  on public.battle_ticket_purchases (user_id, created_at desc);
create index if not exists battle_ticket_purchases_status_idx
  on public.battle_ticket_purchases (status);

drop trigger if exists trg_battle_ticket_purchases_set_updated_at on public.battle_ticket_purchases;
create trigger trg_battle_ticket_purchases_set_updated_at
  before update on public.battle_ticket_purchases
  for each row
  execute function public.tg_set_updated_at();

alter table public.battle_ticket_purchases enable row level security;

-- Edge Functions use service_role and bypass RLS; keep client policies closed by default.
revoke all on public.battle_ticket_purchases from anon, authenticated;

grant select, insert, update, delete on public.battle_ticket_purchases to service_role;

-- Atomic + idempotent: finalize a verified PayChangu battle-ticket purchase.
create or replace function public.apply_battle_ticket_purchase_paychangu(
  p_tx_ref text,
  p_success boolean,
  p_verified_amount numeric,
  p_verified_currency text,
  p_provider_reference text,
  p_provider_status text,
  p_raw jsonb
)
returns table (
  ok boolean,
  idempotent boolean,
  tx_ref text,
  user_id text,
  battle_id text,
  tier text,
  admitted boolean,
  new_sold_quantity int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  pay record;
  ticket record;

  v_tx_ref text;
  v_user_id text;
  v_battle_id text;
  v_tier text;
  v_ticket_id uuid;

  expected_amount numeric;
  expected_currency text;

  sold_after int := 0;
  allow_admit boolean := false;
  within_window boolean := true;
begin
  if p_tx_ref is null or length(trim(p_tx_ref)) = 0 then
    raise exception 'missing_tx_ref' using errcode = 'P0001';
  end if;

  v_tx_ref := trim(p_tx_ref);

  select *
    into pay
    from public.payments
    where provider = 'paychangu'
      and tx_ref = v_tx_ref
    for update;

  if not found then
    return query select false, false, v_tx_ref, null::text, null::text, null::text, false, 0;
    return;
  end if;

  v_user_id := pay.user_id::text;

  if coalesce(pay.purpose, '') <> 'battle_ticket' then
    return query select false, false, v_tx_ref, v_user_id, null::text, null::text, false, 0;
    return;
  end if;

  if pay.verified_at is not null then
    -- Best-effort: include battle/tier if we have a purchase row.
    select battle_id, tier
      into v_battle_id, v_tier
      from public.battle_ticket_purchases
      where provider = 'paychangu'
        and tx_ref = v_tx_ref
      limit 1;

    return query select true, true, v_tx_ref, v_user_id, coalesce(v_battle_id, null::text), coalesce(v_tier, null::text), true, 0;
    return;
  end if;

  expected_amount := pay.amount;
  expected_currency := coalesce(nullif(trim(pay.currency::text), ''), 'MWK');

  v_battle_id := nullif(trim((pay.metadata->>'battle_id')::text), '');
  v_tier := nullif(trim((pay.metadata->>'tier')::text), '');

  begin
    v_ticket_id := nullif(trim((pay.metadata->>'ticket_id')::text), '')::uuid;
  exception when others then
    v_ticket_id := null;
  end;

  -- Metadata required to admit a user.
  if v_battle_id is null or v_tier is null or v_ticket_id is null then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('error', 'missing_ticket_metadata', 'raw', p_raw),
      updated_at = now()
    where id = pay.id;

    update public.battle_ticket_purchases set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      raw = p_raw,
      updated_at = now()
    where provider = 'paychangu'
      and tx_ref = v_tx_ref;

    return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, false, 0;
    return;
  end if;

  -- Ensure we have a corresponding purchases row (idempotent).
  insert into public.battle_ticket_purchases (
    user_id, battle_id, ticket_id, tier,
    provider, tx_ref,
    amount, currency,
    status,
    checkout_url,
    raw,
    created_at, updated_at
  ) values (
    v_user_id,
    v_battle_id,
    v_ticket_id,
    v_tier,
    'paychangu',
    v_tx_ref,
    expected_amount,
    expected_currency,
    'pending',
    pay.checkout_url,
    null,
    now(),
    now()
  )
  on conflict (provider, tx_ref) do update set
    battle_id = excluded.battle_id,
    ticket_id = excluded.ticket_id,
    tier = excluded.tier,
    amount = excluded.amount,
    currency = excluded.currency,
    checkout_url = excluded.checkout_url,
    updated_at = now();

  -- Provider verification.
  if not p_success then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('raw', p_raw),
      updated_at = now()
    where id = pay.id;

    update public.battle_ticket_purchases set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      raw = p_raw,
      updated_at = now()
    where provider = 'paychangu'
      and tx_ref = v_tx_ref;

    return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, false, 0;
    return;
  end if;

  if p_verified_amount < expected_amount or upper(coalesce(nullif(trim(p_verified_currency), ''), 'MWK')) <> upper(expected_currency) then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'error', 'verification_mismatch',
        'verified_amount', p_verified_amount,
        'verified_currency', p_verified_currency,
        'raw', p_raw
      ),
      updated_at = now()
    where id = pay.id;

    update public.battle_ticket_purchases set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      raw = p_raw,
      updated_at = now()
    where provider = 'paychangu'
      and tx_ref = v_tx_ref;

    return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, false, 0;
    return;
  end if;

  -- Lock and validate ticket inventory.
  select * into ticket
    from public.battle_tickets
    where id = v_ticket_id
    for update;

  if not found then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('error', 'ticket_not_found', 'raw', p_raw),
      updated_at = now()
    where id = pay.id;

    update public.battle_ticket_purchases set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      raw = p_raw,
      updated_at = now()
    where provider = 'paychangu'
      and tx_ref = v_tx_ref;

    return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, false, 0;
    return;
  end if;

  if ticket.battle_id is distinct from v_battle_id or ticket.tier is distinct from v_tier then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('error', 'ticket_mismatch', 'raw', p_raw),
      updated_at = now()
    where id = pay.id;

    update public.battle_ticket_purchases set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      raw = p_raw,
      updated_at = now()
    where provider = 'paychangu'
      and tx_ref = v_tx_ref;

    return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, false, 0;
    return;
  end if;

  within_window := true;
  if ticket.sale_start_at is not null and now() < ticket.sale_start_at then
    within_window := false;
  end if;
  if ticket.sale_end_at is not null and now() > ticket.sale_end_at then
    within_window := false;
  end if;

  allow_admit := coalesce(ticket.sales_enabled, true)
    and coalesce(ticket.is_active, true)
    and within_window
    and coalesce(ticket.sold_quantity, 0) < coalesce(ticket.quantity_total, 0);

  if not allow_admit then
    update public.payments set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('error', 'inventory_unavailable', 'raw', p_raw),
      updated_at = now()
    where id = pay.id;

    update public.battle_ticket_purchases set
      status = 'failed',
      provider_reference = p_provider_reference,
      provider_status = p_provider_status,
      verified_at = now(),
      raw = p_raw,
      updated_at = now()
    where provider = 'paychangu'
      and tx_ref = v_tx_ref;

    return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, false, 0;
    return;
  end if;

  update public.battle_tickets
    set sold_quantity = sold_quantity + 1,
        updated_at = now()
    where id = v_ticket_id
    returning sold_quantity into sold_after;

  update public.payments set
    status = 'success',
    provider_reference = p_provider_reference,
    provider_status = p_provider_status,
    verified_at = now(),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'battle_id', v_battle_id,
      'ticket_id', v_ticket_id,
      'tier', v_tier,
      'raw', p_raw
    ),
    updated_at = now()
  where id = pay.id;

  update public.battle_ticket_purchases set
    status = 'success',
    provider_reference = p_provider_reference,
    provider_status = p_provider_status,
    verified_at = now(),
    raw = p_raw,
    updated_at = now()
  where provider = 'paychangu'
    and tx_ref = v_tx_ref;

  return query select true, false, v_tx_ref, v_user_id, v_battle_id, v_tier, true, sold_after;
end;
$$;

revoke all on function public.apply_battle_ticket_purchase_paychangu(text, boolean, numeric, text, text, text, jsonb) from public;
grant execute on function public.apply_battle_ticket_purchase_paychangu(text, boolean, numeric, text, text, text, jsonb) to service_role;

notify pgrst, 'reload schema';
