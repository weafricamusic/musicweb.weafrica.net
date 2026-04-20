-- Events + Tickets (admin-managed)
-- Admin uses service role; RLS is deny-all by default.

create extension if not exists pgcrypto;
-- Ensure the shared updated_at trigger helper exists.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
-- If these objects already exist (e.g. a previous partial run), ensure required columns
-- exist before we create indexes/triggers that depend on them.
do $$
begin
  if to_regclass('public.ticketing_events') is not null then
    alter table public.ticketing_events
      add column if not exists title text,
      add column if not exists description text,
      add column if not exists cover_image_url text not null default '',
      add column if not exists venue_name text,
      add column if not exists venue_address text,
      add column if not exists city text,
      add column if not exists country_code text,
      add column if not exists starts_at timestamptz,
      add column if not exists ends_at timestamptz,
      add column if not exists timezone text not null default 'UTC',
      add column if not exists status text not null default 'draft',
      add column if not exists created_by_admin_email text,
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists updated_at timestamptz not null default now();
  end if;

  if to_regclass('public.ticketing_ticket_types') is not null then
    alter table public.ticketing_ticket_types
      add column if not exists event_id uuid,
      add column if not exists name text,
      add column if not exists description text,
      add column if not exists price_cents int not null default 0,
      add column if not exists currency_code text not null default 'USD',
      add column if not exists quantity_total int not null default 0,
      add column if not exists quantity_sold int not null default 0,
      add column if not exists sales_start_at timestamptz,
      add column if not exists sales_end_at timestamptz,
      add column if not exists is_active boolean not null default true,
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists updated_at timestamptz not null default now();
  end if;

  if to_regclass('public.ticketing_ticket_orders') is not null then
    alter table public.ticketing_ticket_orders
      add column if not exists event_id uuid,
      add column if not exists buyer_name text,
      add column if not exists buyer_email text,
      add column if not exists buyer_phone text,
      add column if not exists status text not null default 'paid',
      add column if not exists payment_provider text,
      add column if not exists payment_reference text,
      add column if not exists total_amount_cents int not null default 0,
      add column if not exists currency_code text not null default 'USD',
      add column if not exists created_by_admin_email text,
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists updated_at timestamptz not null default now();
  end if;

  if to_regclass('public.ticketing_ticket_order_items') is not null then
    alter table public.ticketing_ticket_order_items
      add column if not exists order_id uuid,
      add column if not exists ticket_type_id uuid,
      add column if not exists ticket_type_name text,
      add column if not exists quantity int,
      add column if not exists unit_price_cents int not null default 0,
      add column if not exists line_total_cents int not null default 0,
      add column if not exists created_at timestamptz not null default now();
  end if;

  if to_regclass('public.ticketing_tickets') is not null then
    alter table public.ticketing_tickets
      add column if not exists event_id uuid,
      add column if not exists ticket_type_id uuid,
      add column if not exists order_id uuid,
      add column if not exists code text not null default '',
      add column if not exists status text not null default 'issued',
      add column if not exists issued_at timestamptz not null default now(),
      add column if not exists checked_in_at timestamptz,
      add column if not exists scanned_by_admin_email text;
  end if;
end $$;
-- NOTE: These tables are namespaced to avoid collisions with other apps/projects
-- that may already have a `public.events` table.

create table if not exists public.ticketing_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  cover_image_url text not null default '',
  venue_name text,
  venue_address text,
  city text,
  country_code text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  timezone text not null default 'UTC',
  status text not null default 'draft' check (status in ('draft','published','cancelled')),
  created_by_admin_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Upgrade safety: if the table already existed, ensure columns referenced by indexes exist.
alter table public.ticketing_events
  add column if not exists status text;
create index if not exists ticketing_events_starts_at_idx on public.ticketing_events (starts_at);
create index if not exists ticketing_events_status_idx on public.ticketing_events (status);
create index if not exists ticketing_events_country_idx on public.ticketing_events (country_code);
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ticketing_events_set_updated_at') then
    create trigger ticketing_events_set_updated_at
      before update on public.ticketing_events
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;
alter table public.ticketing_events enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_events'
      and policyname = 'deny_all_ticketing_events'
  ) then
    create policy deny_all_ticketing_events
      on public.ticketing_events
      for all
      using (false)
      with check (false);
  end if;
end $$;
create table if not exists public.ticketing_ticket_types (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.ticketing_events(id) on delete cascade,
  name text not null,
  description text,
  price_cents int not null check (price_cents >= 0),
  currency_code text not null default 'USD',
  quantity_total int not null check (quantity_total >= 0),
  quantity_sold int not null default 0 check (quantity_sold >= 0),
  sales_start_at timestamptz,
  sales_end_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_types_sold_le_total check (quantity_sold <= quantity_total)
);
create index if not exists ticketing_ticket_types_event_idx on public.ticketing_ticket_types (event_id);
create index if not exists ticketing_ticket_types_active_idx on public.ticketing_ticket_types (is_active);
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ticketing_ticket_types_set_updated_at') then
    create trigger ticketing_ticket_types_set_updated_at
      before update on public.ticketing_ticket_types
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;
alter table public.ticketing_ticket_types enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_ticket_types'
      and policyname = 'deny_all_ticketing_ticket_types'
  ) then
    create policy deny_all_ticketing_ticket_types
      on public.ticketing_ticket_types
      for all
      using (false)
      with check (false);
  end if;
end $$;
create table if not exists public.ticketing_ticket_orders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.ticketing_events(id) on delete cascade,
  buyer_name text,
  buyer_email text,
  buyer_phone text,
  status text not null default 'paid' check (status in ('pending','paid','cancelled','refunded')),
  payment_provider text,
  payment_reference text,
  total_amount_cents int not null default 0 check (total_amount_cents >= 0),
  currency_code text not null default 'USD',
  created_by_admin_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Upgrade safety: ensure columns referenced by indexes exist.
alter table public.ticketing_ticket_orders
  add column if not exists status text;
create index if not exists ticketing_ticket_orders_event_idx on public.ticketing_ticket_orders (event_id);
create index if not exists ticketing_ticket_orders_created_at_idx on public.ticketing_ticket_orders (created_at desc);
create index if not exists ticketing_ticket_orders_status_idx on public.ticketing_ticket_orders (status);
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ticketing_ticket_orders_set_updated_at') then
    create trigger ticketing_ticket_orders_set_updated_at
      before update on public.ticketing_ticket_orders
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;
alter table public.ticketing_ticket_orders enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_ticket_orders'
      and policyname = 'deny_all_ticketing_ticket_orders'
  ) then
    create policy deny_all_ticketing_ticket_orders
      on public.ticketing_ticket_orders
      for all
      using (false)
      with check (false);
  end if;
end $$;
create table if not exists public.ticketing_ticket_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.ticketing_ticket_orders(id) on delete cascade,
  ticket_type_id uuid not null references public.ticketing_ticket_types(id),
  ticket_type_name text not null,
  quantity int not null check (quantity > 0),
  unit_price_cents int not null check (unit_price_cents >= 0),
  line_total_cents int not null check (line_total_cents >= 0),
  created_at timestamptz not null default now()
);
create index if not exists ticketing_ticket_order_items_order_idx on public.ticketing_ticket_order_items (order_id);
create index if not exists ticketing_ticket_order_items_type_idx on public.ticketing_ticket_order_items (ticket_type_id);
alter table public.ticketing_ticket_order_items enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_ticket_order_items'
      and policyname = 'deny_all_ticketing_ticket_order_items'
  ) then
    create policy deny_all_ticketing_ticket_order_items
      on public.ticketing_ticket_order_items
      for all
      using (false)
      with check (false);
  end if;
end $$;
create table if not exists public.ticketing_tickets (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.ticketing_events(id) on delete cascade,
  ticket_type_id uuid not null references public.ticketing_ticket_types(id),
  order_id uuid not null references public.ticketing_ticket_orders(id) on delete cascade,
  code text not null,
  status text not null default 'issued' check (status in ('issued','voided','checked_in')),
  issued_at timestamptz not null default now(),
  checked_in_at timestamptz,
  scanned_by_admin_email text
);
alter table public.ticketing_tickets
  add column if not exists status text;
create unique index if not exists ticketing_tickets_code_uniq on public.ticketing_tickets (code);
create index if not exists ticketing_tickets_order_idx on public.ticketing_tickets (order_id);
create index if not exists ticketing_tickets_event_idx on public.ticketing_tickets (event_id);
create index if not exists ticketing_tickets_type_idx on public.ticketing_tickets (ticket_type_id);
alter table public.ticketing_tickets enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ticketing_tickets'
      and policyname = 'deny_all_ticketing_tickets'
  ) then
    create policy deny_all_ticketing_tickets
      on public.ticketing_tickets
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- Atomic order creation + inventory reservation + ticket issuance.
-- Intended for admin/service-role usage.
create or replace function public.ticketing_create_order(
  p_event_id uuid,
  p_buyer_name text,
  p_buyer_email text,
  p_buyer_phone text,
  p_items jsonb,
  p_status text default 'paid',
  p_payment_provider text default null,
  p_payment_reference text default null,
  p_created_by_admin_email text default null
) returns uuid
language plpgsql
security definer
as $$
declare
  v_order_id uuid := gen_random_uuid();
  v_currency text := null;
  v_total int := 0;
  v_item jsonb;
  v_qty int;
  v_ticket_type record;
  i int;
  v_code text;
  v_status text;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'items is required';
  end if;

  v_status := coalesce(nullif(trim(p_status), ''), 'paid');
  if v_status not in ('pending','paid','cancelled','refunded') then
    raise exception 'invalid status';
  end if;

  insert into public.ticketing_ticket_orders (
    id, event_id,
    buyer_name, buyer_email, buyer_phone,
    status, payment_provider, payment_reference,
    total_amount_cents, currency_code,
    created_by_admin_email
  ) values (
    v_order_id, p_event_id,
    nullif(trim(p_buyer_name), ''),
    nullif(trim(lower(p_buyer_email)), ''),
    nullif(trim(p_buyer_phone), ''),
    v_status,
    nullif(trim(p_payment_provider), ''),
    nullif(trim(p_payment_reference), ''),
    0,
    'USD',
    nullif(trim(p_created_by_admin_email), '')
  );

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := nullif((v_item->>'quantity')::int, 0);
    if v_qty is null or v_qty <= 0 then
      raise exception 'quantity must be > 0';
    end if;

    select
      tt.id,
      tt.event_id,
      tt.name,
      tt.price_cents,
      tt.currency_code,
      tt.quantity_total,
      tt.quantity_sold,
      tt.is_active,
      tt.sales_start_at,
      tt.sales_end_at
    into v_ticket_type
    from public.ticketing_ticket_types tt
    where tt.id = (v_item->>'ticket_type_id')::uuid
    for update;

    if not found then
      raise exception 'ticket_type not found';
    end if;

    if v_ticket_type.event_id <> p_event_id then
      raise exception 'ticket_type event mismatch';
    end if;

    if v_ticket_type.is_active is not true then
      raise exception 'ticket_type inactive';
    end if;

    if v_ticket_type.sales_start_at is not null and now() < v_ticket_type.sales_start_at then
      raise exception 'sales not started';
    end if;

    if v_ticket_type.sales_end_at is not null and now() > v_ticket_type.sales_end_at then
      raise exception 'sales ended';
    end if;

    if (v_ticket_type.quantity_sold + v_qty) > v_ticket_type.quantity_total then
      raise exception 'not enough inventory';
    end if;

    if v_currency is null then
      v_currency := v_ticket_type.currency_code;
    elsif v_ticket_type.currency_code <> v_currency then
      raise exception 'mixed currency not supported';
    end if;

    insert into public.ticketing_ticket_order_items (
      order_id, ticket_type_id, ticket_type_name,
      quantity, unit_price_cents, line_total_cents
    ) values (
      v_order_id,
      v_ticket_type.id,
      v_ticket_type.name,
      v_qty,
      v_ticket_type.price_cents,
      (v_ticket_type.price_cents * v_qty)
    );

    update public.ticketing_ticket_types
      set quantity_sold = quantity_sold + v_qty
      where id = v_ticket_type.id;

    v_total := v_total + (v_ticket_type.price_cents * v_qty);

    -- Issue one ticket per quantity.
    for i in 1..v_qty loop
      v_code := encode(gen_random_bytes(10), 'hex');
      insert into public.ticketing_tickets (
        event_id, ticket_type_id, order_id, code, status, issued_at
      ) values (
        p_event_id, v_ticket_type.id, v_order_id, v_code, 'issued', now()
      );
    end loop;
  end loop;

  update public.ticketing_ticket_orders
    set total_amount_cents = v_total,
        currency_code = coalesce(v_currency, 'USD'),
        updated_at = now()
    where id = v_order_id;

  return v_order_id;
end;
$$;
-- Harden RPC: avoid search_path injection and ensure it's not callable from client roles.
alter function public.ticketing_create_order(
  uuid, text, text, text, jsonb, text, text, text, text
) set search_path = public;
do $$
begin
  revoke all on function public.ticketing_create_order(
    uuid, text, text, text, jsonb, text, text, text, text
  ) from public;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.ticketing_create_order(
      uuid, text, text, text, jsonb, text, text, text, text
    ) to service_role;
  end if;
end $$;
-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';
