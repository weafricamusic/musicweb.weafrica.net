-- Events & Ticket Sales schema alignment + RLS
--
-- This project uses Firebase UID as TEXT (see `public.profiles.id`).
-- These tables are designed to be easy to bind from Flutter while remaining scalable.
--
-- Creates/aligns:
--   - public.events
--   - public.event_tickets
--   - public.ticket_orders
--   - public.user_tickets
--   - public.promoted_events
--
-- Adds:
--   - indexes for upcoming events and lookups
--   - updated_at triggers
--   - ticket inventory enforcement + sold counter trigger
--   - RLS policies (artist/user/admin)

create extension if not exists pgcrypto;
-- 1) Create tables if they don't exist (fresh installs)

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  artist_id text,
  title text,
  description text,
  poster_url text,
  date_time timestamptz,
  location text,
  is_online boolean not null default false,
  is_live boolean not null default false,
  is_sponsored boolean not null default false,
  currency text not null default 'MWK',
  starting_price numeric not null default 0,
  status text not null default 'Draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.event_tickets (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  type_name text not null,
  price numeric not null default 0,
  quantity integer not null default 0,
  sold integer not null default 0,
  currency text not null default 'MWK',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.ticket_orders (
  id uuid primary key default gen_random_uuid(),
  user_id text,
  ticket_id uuid references public.event_tickets(id) on delete restrict,
  quantity integer not null default 1,
  total_price numeric not null default 0,
  payment_status text not null default 'Pending',
  payment_method text,
  order_date timestamptz not null default now(),
  qr_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.user_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id text,
  order_id uuid references public.ticket_orders(id) on delete set null,
  ticket_id uuid references public.event_tickets(id) on delete restrict,
  qr_code text,
  status text not null default 'Valid',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.promoted_events (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  start_date timestamptz not null default now(),
  end_date timestamptz,
  budget numeric not null default 0,
  placement text not null default 'Home',
  status text not null default 'Pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- 2) Align existing columns from prior migrations (best-effort, idempotent)

do $$
begin
  -- EVENTS
  if to_regclass('public.events') is not null then
    -- rename `name` -> `title`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='name'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='title'
    ) then
      execute 'alter table public.events rename column name to title';
    end if;

    -- rename `starts_at` -> `date_time`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='starts_at'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='date_time'
    ) then
      execute 'alter table public.events rename column starts_at to date_time';
    end if;

    -- rename `host_user_id` -> `artist_id`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='host_user_id'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='artist_id'
    ) then
      execute 'alter table public.events rename column host_user_id to artist_id';
    end if;

    -- add missing columns
    execute 'alter table public.events add column if not exists description text';
    execute 'alter table public.events add column if not exists location text';
    execute 'alter table public.events add column if not exists is_live boolean not null default false';
    execute 'alter table public.events add column if not exists is_sponsored boolean not null default false';
    execute 'alter table public.events add column if not exists currency text not null default ''MWK''';
    execute 'alter table public.events add column if not exists starting_price numeric not null default 0';

    -- best-effort: map old venue/city into `location` if empty
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='venue'
    ) then
      execute $sql$
        update public.events
        set location = nullif(trim(both ', ' from concat_ws(', ', venue, city)), '')
        where (location is null or btrim(location) = '')
      $sql$;
    end if;

    -- normalize status values to Title Case
    execute $sql$
      update public.events
      set status = case
        when lower(status) = 'draft' then 'Draft'
        when lower(status) = 'published' then 'Published'
        when lower(status) = 'completed' then 'Completed'
        else status
      end
      where status is not null
    $sql$;

    -- ensure defaults/non-null on key columns (best-effort)
    execute 'alter table public.events alter column status set default ''Draft''';
    execute 'alter table public.events alter column currency set default ''MWK''';

    -- FK to profiles (Firebase UID text) if possible
    begin
      execute 'alter table public.events drop constraint if exists events_artist_id_fkey';
    exception when undefined_object then
      null;
    end;

    begin
      execute 'alter table public.events add constraint events_artist_id_fkey foreign key (artist_id) references public.profiles(id) on delete restrict';
    exception when others then
      -- ignore if profiles missing or existing data breaks
      null;
    end;

    -- checks
    begin
      execute 'alter table public.events drop constraint if exists events_status_check';
    exception when undefined_object then
      null;
    end;

    begin
      execute 'alter table public.events add constraint events_status_check check (status in (''Draft'',''Published'',''Completed''))';
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.events drop constraint if exists events_starting_price_check';
    exception when undefined_object then
      null;
    end;

    begin
      execute 'alter table public.events add constraint events_starting_price_check check (starting_price >= 0)';
    exception when others then
      null;
    end;
  end if;

  -- EVENT_TICKETS
  if to_regclass('public.event_tickets') is not null then
    -- rename `name` -> `type_name`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='event_tickets' and column_name='name'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='event_tickets' and column_name='type_name'
    ) then
      execute 'alter table public.event_tickets rename column name to type_name';
    end if;

    -- best-effort: migrate price_mwk -> price
    execute 'alter table public.event_tickets add column if not exists price numeric';
    execute 'alter table public.event_tickets add column if not exists currency text not null default ''MWK''';
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='event_tickets' and column_name='price_mwk'
    ) then
      execute 'update public.event_tickets set price = price_mwk where price is null';
    end if;
    execute 'alter table public.event_tickets alter column price set default 0';
    execute 'alter table public.event_tickets alter column price set not null';

    -- best-effort: migrate capacity -> quantity
    execute 'alter table public.event_tickets add column if not exists quantity integer';
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='event_tickets' and column_name='capacity'
    ) then
      execute 'update public.event_tickets set quantity = capacity where quantity is null';
    end if;
    execute 'update public.event_tickets set quantity = 0 where quantity is null';
    execute 'alter table public.event_tickets alter column quantity set default 0';
    execute 'alter table public.event_tickets alter column quantity set not null';

    execute 'alter table public.event_tickets add column if not exists sold integer not null default 0';

    begin
      execute 'alter table public.event_tickets drop constraint if exists event_tickets_quantity_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.event_tickets add constraint event_tickets_quantity_check check (quantity >= 0)';
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.event_tickets drop constraint if exists event_tickets_price_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.event_tickets add constraint event_tickets_price_check check (price >= 0)';
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.event_tickets drop constraint if exists event_tickets_sold_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.event_tickets add constraint event_tickets_sold_check check (sold >= 0 and sold <= quantity)';
    exception when others then
      null;
    end;

    begin
      execute 'create unique index if not exists event_tickets_event_type_uniq on public.event_tickets (event_id, type_name)';
    exception when others then
      null;
    end;
  end if;

  -- TICKET_ORDERS
  if to_regclass('public.ticket_orders') is not null then
    -- rename `ticket_type_id` -> `ticket_id`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='ticket_orders' and column_name='ticket_type_id'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='ticket_orders' and column_name='ticket_id'
    ) then
      execute 'alter table public.ticket_orders rename column ticket_type_id to ticket_id';
    end if;

    -- total_mwk -> total_price
    execute 'alter table public.ticket_orders add column if not exists total_price numeric';
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='ticket_orders' and column_name='total_mwk'
    ) then
      execute 'update public.ticket_orders set total_price = total_mwk where total_price is null';
    end if;
    execute 'update public.ticket_orders set total_price = 0 where total_price is null';
    execute 'alter table public.ticket_orders alter column total_price set default 0';
    execute 'alter table public.ticket_orders alter column total_price set not null';

    -- status -> payment_status
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='ticket_orders' and column_name='status'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='ticket_orders' and column_name='payment_status'
    ) then
      execute 'alter table public.ticket_orders rename column status to payment_status';
    end if;

    execute 'alter table public.ticket_orders alter column payment_status set default ''Pending''';

    execute 'alter table public.ticket_orders add column if not exists order_date timestamptz not null default now()';
    execute 'alter table public.ticket_orders add column if not exists qr_code text';

    -- backfill order_date from created_at
    execute 'update public.ticket_orders set order_date = created_at where order_date is null';

    -- normalize payment_status to Title Case
    execute $sql$
      update public.ticket_orders
      set payment_status = case
        when lower(payment_status) = 'pending' then 'Pending'
        when lower(payment_status) = 'paid' then 'Paid'
        when lower(payment_status) = 'failed' then 'Failed'
        else payment_status
      end
      where payment_status is not null
    $sql$;

    -- FK to profiles
    begin
      execute 'alter table public.ticket_orders drop constraint if exists ticket_orders_user_id_fkey';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.ticket_orders add constraint ticket_orders_user_id_fkey foreign key (user_id) references public.profiles(id) on delete restrict';
    exception when others then
      null;
    end;

    -- checks
    begin
      execute 'alter table public.ticket_orders drop constraint if exists ticket_orders_payment_status_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.ticket_orders add constraint ticket_orders_payment_status_check check (payment_status in (''Pending'',''Paid'',''Failed''))';
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.ticket_orders drop constraint if exists ticket_orders_quantity_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.ticket_orders add constraint ticket_orders_quantity_check check (quantity > 0)';
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.ticket_orders drop constraint if exists ticket_orders_total_price_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.ticket_orders add constraint ticket_orders_total_price_check check (total_price >= 0)';
    exception when others then
      null;
    end;
  end if;

  -- USER_TICKETS
  if to_regclass('public.user_tickets') is not null then
    -- rename `ticket_type_id` -> `ticket_id`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='user_tickets' and column_name='ticket_type_id'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='user_tickets' and column_name='ticket_id'
    ) then
      execute 'alter table public.user_tickets rename column ticket_type_id to ticket_id';
    end if;

    -- rename `qr_payload` -> `qr_code`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='user_tickets' and column_name='qr_payload'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='user_tickets' and column_name='qr_code'
    ) then
      execute 'alter table public.user_tickets rename column qr_payload to qr_code';
    end if;

    -- add missing columns
    execute 'alter table public.user_tickets add column if not exists qr_code text';

    -- status defaults/normalization
    execute 'alter table public.user_tickets alter column status set default ''Valid''';

    execute $sql$
      update public.user_tickets
      set status = case
        when lower(status) = 'valid' then 'Valid'
        when lower(status) = 'used' then 'Used'
        when lower(status) = 'expired' then 'Expired'
        else status
      end
      where status is not null
    $sql$;

    -- FK to profiles
    begin
      execute 'alter table public.user_tickets drop constraint if exists user_tickets_user_id_fkey';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.user_tickets add constraint user_tickets_user_id_fkey foreign key (user_id) references public.profiles(id) on delete restrict';
    exception when others then
      null;
    end;

    -- checks + uniqueness
    begin
      execute 'alter table public.user_tickets drop constraint if exists user_tickets_status_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.user_tickets add constraint user_tickets_status_check check (status in (''Valid'',''Used'',''Expired''))';
    exception when others then
      null;
    end;

    begin
      execute 'create unique index if not exists user_tickets_qr_code_uniq on public.user_tickets (qr_code)';
    exception when others then
      null;
    end;
  end if;

  -- PROMOTED_EVENTS
  if to_regclass('public.promoted_events') is not null then
    -- rename `starts_at` -> `start_date`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='promoted_events' and column_name='starts_at'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='promoted_events' and column_name='start_date'
    ) then
      execute 'alter table public.promoted_events rename column starts_at to start_date';
    end if;

    -- rename `ends_at` -> `end_date`
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='promoted_events' and column_name='ends_at'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='promoted_events' and column_name='end_date'
    ) then
      execute 'alter table public.promoted_events rename column ends_at to end_date';
    end if;

    execute 'alter table public.promoted_events add column if not exists budget numeric not null default 0';
    execute 'alter table public.promoted_events add column if not exists placement text not null default ''Home''';
    execute 'alter table public.promoted_events add column if not exists status text not null default ''Pending''';
    execute 'alter table public.promoted_events add column if not exists updated_at timestamptz not null default now()';

    -- map legacy placement flags to placement text
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='promoted_events' and column_name='placement_home'
    ) then
      execute $sql$
        update public.promoted_events
        set placement = case
          when placement_push is true then 'Push Notification'
          when placement_events_top is true then 'Top of Events'
          else 'Home'
        end
        where placement is null or btrim(placement) = ''
      $sql$;
    end if;

    -- normalize status values
    execute $sql$
      update public.promoted_events
      set status = case
        when lower(status) = 'pending' then 'Pending'
        when lower(status) = 'approved' then 'Approved'
        when lower(status) = 'active' then 'Active'
        when lower(status) = 'completed' then 'Completed'
        else status
      end
      where status is not null
    $sql$;

    begin
      execute 'alter table public.promoted_events drop constraint if exists promoted_events_status_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.promoted_events add constraint promoted_events_status_check check (status in (''Pending'',''Approved'',''Active'',''Completed''))';
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.promoted_events drop constraint if exists promoted_events_budget_check';
    exception when undefined_object then
      null;
    end;
    begin
      execute 'alter table public.promoted_events add constraint promoted_events_budget_check check (budget >= 0)';
    exception when others then
      null;
    end;
  end if;
end $$;
-- 3) Indexes (fast upcoming events + joins)

create index if not exists events_date_time_idx on public.events (date_time asc);
create index if not exists events_status_date_time_idx on public.events (status, date_time asc);
create index if not exists events_artist_id_idx on public.events (artist_id);
create index if not exists event_tickets_event_id_idx on public.event_tickets (event_id);
create index if not exists ticket_orders_user_id_idx on public.ticket_orders (user_id);
create index if not exists ticket_orders_ticket_id_idx on public.ticket_orders (ticket_id);
create index if not exists ticket_orders_order_date_idx on public.ticket_orders (order_date desc);
create index if not exists user_tickets_user_id_idx on public.user_tickets (user_id);
create index if not exists user_tickets_ticket_id_idx on public.user_tickets (ticket_id);
create index if not exists user_tickets_status_idx on public.user_tickets (status);
create index if not exists promoted_events_event_id_idx on public.promoted_events (event_id);
create index if not exists promoted_events_status_idx on public.promoted_events (status);
create index if not exists promoted_events_start_date_idx on public.promoted_events (start_date desc);
-- 4) updated_at trigger

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
do $$
begin
  -- EVENTS
  if to_regclass('public.events') is not null then
    execute 'drop trigger if exists trg_events_set_updated_at on public.events';
    execute 'create trigger trg_events_set_updated_at before update on public.events for each row execute function public.set_updated_at()';
  end if;

  -- EVENT_TICKETS
  if to_regclass('public.event_tickets') is not null then
    execute 'drop trigger if exists trg_event_tickets_set_updated_at on public.event_tickets';
    execute 'create trigger trg_event_tickets_set_updated_at before update on public.event_tickets for each row execute function public.set_updated_at()';
  end if;

  -- TICKET_ORDERS
  if to_regclass('public.ticket_orders') is not null then
    execute 'drop trigger if exists trg_ticket_orders_set_updated_at on public.ticket_orders';
    execute 'create trigger trg_ticket_orders_set_updated_at before update on public.ticket_orders for each row execute function public.set_updated_at()';
  end if;

  -- USER_TICKETS
  if to_regclass('public.user_tickets') is not null then
    execute 'drop trigger if exists trg_user_tickets_set_updated_at on public.user_tickets';
    execute 'create trigger trg_user_tickets_set_updated_at before update on public.user_tickets for each row execute function public.set_updated_at()';
  end if;

  -- PROMOTED_EVENTS
  if to_regclass('public.promoted_events') is not null then
    execute 'drop trigger if exists trg_promoted_events_set_updated_at on public.promoted_events';
    execute 'create trigger trg_promoted_events_set_updated_at before update on public.promoted_events for each row execute function public.set_updated_at()';
  end if;
end $$;
-- 5) Ticket inventory enforcement + sold counter

create or replace function public.assert_ticket_inventory()
returns trigger
language plpgsql
as $$
declare
  v_qty integer;
  v_sold integer;
begin
  if new.ticket_id is null then
    return new;
  end if;

  select quantity, sold into v_qty, v_sold
  from public.event_tickets
  where id = new.ticket_id
  for update;

  if v_qty is null then
    raise exception 'Ticket type not found';
  end if;

  if v_sold >= v_qty then
    raise exception 'Ticket sold out';
  end if;

  return new;
end;
$$;
create or replace function public.recompute_ticket_sold()
returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'INSERT') then
    if new.ticket_id is not null then
      update public.event_tickets
      set sold = (
        select count(*)
        from public.user_tickets ut
        where ut.ticket_id = new.ticket_id
          and ut.status in ('Valid','Used')
      )
      where id = new.ticket_id;
    end if;
    return null;
  end if;

  if (tg_op = 'DELETE') then
    if old.ticket_id is not null then
      update public.event_tickets
      set sold = (
        select count(*)
        from public.user_tickets ut
        where ut.ticket_id = old.ticket_id
          and ut.status in ('Valid','Used')
      )
      where id = old.ticket_id;
    end if;
    return null;
  end if;

  -- UPDATE
  if new.ticket_id is distinct from old.ticket_id then
    if old.ticket_id is not null then
      update public.event_tickets
      set sold = (
        select count(*)
        from public.user_tickets ut
        where ut.ticket_id = old.ticket_id
          and ut.status in ('Valid','Used')
      )
      where id = old.ticket_id;
    end if;
  end if;

  if new.ticket_id is not null then
    update public.event_tickets
    set sold = (
      select count(*)
      from public.user_tickets ut
      where ut.ticket_id = new.ticket_id
        and ut.status in ('Valid','Used')
    )
    where id = new.ticket_id;
  end if;

  return null;
end;
$$;
do $$
begin
  if to_regclass('public.user_tickets') is not null then
    execute 'drop trigger if exists trg_user_tickets_assert_inventory on public.user_tickets';
    execute 'create trigger trg_user_tickets_assert_inventory before insert on public.user_tickets for each row execute function public.assert_ticket_inventory()';

    execute 'drop trigger if exists trg_user_tickets_recompute_sold on public.user_tickets';
    execute 'create trigger trg_user_tickets_recompute_sold after insert or delete or update of ticket_id, status on public.user_tickets for each row execute function public.recompute_ticket_sold()';
  end if;
end $$;
-- 6) RLS policies

-- Helper: admin role check using public.user_roles (Firebase UID text)
create or replace function public.is_platform_admin(uid text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = uid
      and ur.role in ('admin','super_admin','finance_admin','moderator')
      and coalesce(ur.is_active, true) = true
  );
$$;
-- EVENTS
alter table public.events enable row level security;
drop policy if exists "events public read" on public.events;
drop policy if exists "events artist manage" on public.events;
drop policy if exists "events admin manage" on public.events;
create policy "events public read" on public.events
  for select
  using (status = 'Published');
create policy "events artist manage" on public.events
  for all
  using (artist_id = auth.uid()::text)
  with check (artist_id = auth.uid()::text);
create policy "events admin manage" on public.events
  for all
  using (public.is_platform_admin(auth.uid()::text))
  with check (public.is_platform_admin(auth.uid()::text));
-- EVENT_TICKETS
alter table public.event_tickets enable row level security;
drop policy if exists "event_tickets public read" on public.event_tickets;
drop policy if exists "event_tickets artist manage" on public.event_tickets;
drop policy if exists "event_tickets admin manage" on public.event_tickets;
create policy "event_tickets public read" on public.event_tickets
  for select
  using (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.status = 'Published'
    )
  );
create policy "event_tickets artist manage" on public.event_tickets
  for all
  using (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
    )
  )
  with check (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
    )
  );
create policy "event_tickets admin manage" on public.event_tickets
  for all
  using (public.is_platform_admin(auth.uid()::text))
  with check (public.is_platform_admin(auth.uid()::text));
-- TICKET_ORDERS
alter table public.ticket_orders enable row level security;
drop policy if exists "ticket_orders buyer read" on public.ticket_orders;
drop policy if exists "ticket_orders buyer create" on public.ticket_orders;
drop policy if exists "ticket_orders host read" on public.ticket_orders;
drop policy if exists "ticket_orders admin manage" on public.ticket_orders;
create policy "ticket_orders buyer read" on public.ticket_orders
  for select
  using (user_id = auth.uid()::text);
create policy "ticket_orders buyer create" on public.ticket_orders
  for insert
  with check (user_id = auth.uid()::text);
-- Allow hosts to see orders for their events (useful for attendee list)
create policy "ticket_orders host read" on public.ticket_orders
  for select
  using (
    exists (
      select 1
      from public.event_tickets et
      join public.events e on e.id = et.event_id
      where et.id = ticket_orders.ticket_id
        and e.artist_id = auth.uid()::text
    )
  );
create policy "ticket_orders admin manage" on public.ticket_orders
  for all
  using (public.is_platform_admin(auth.uid()::text))
  with check (public.is_platform_admin(auth.uid()::text));
-- USER_TICKETS
alter table public.user_tickets enable row level security;
drop policy if exists "user_tickets owner read" on public.user_tickets;
drop policy if exists "user_tickets owner create" on public.user_tickets;
drop policy if exists "user_tickets host read" on public.user_tickets;
drop policy if exists "user_tickets admin manage" on public.user_tickets;
create policy "user_tickets owner read" on public.user_tickets
  for select
  using (user_id = auth.uid()::text);
create policy "user_tickets owner create" on public.user_tickets
  for insert
  with check (user_id = auth.uid()::text);
-- Host/artist can read tickets for check-in scans
create policy "user_tickets host read" on public.user_tickets
  for select
  using (
    exists (
      select 1
      from public.event_tickets et
      join public.events e on e.id = et.event_id
      where et.id = user_tickets.ticket_id
        and e.artist_id = auth.uid()::text
    )
  );
create policy "user_tickets admin manage" on public.user_tickets
  for all
  using (public.is_platform_admin(auth.uid()::text))
  with check (public.is_platform_admin(auth.uid()::text));
-- PROMOTED_EVENTS
alter table public.promoted_events enable row level security;
drop policy if exists "promoted_events public read" on public.promoted_events;
drop policy if exists "promoted_events artist request" on public.promoted_events;
drop policy if exists "promoted_events artist read" on public.promoted_events;
drop policy if exists "promoted_events admin manage" on public.promoted_events;
-- Public can read active promotions (e.g., home carousel)
create policy "promoted_events public read" on public.promoted_events
  for select
  using (
    status = 'Active'
    and now() >= start_date
    and (end_date is null or now() <= end_date)
  );
-- Artists can request promotion for their own event (creates as Pending)
create policy "promoted_events artist request" on public.promoted_events
  for insert
  with check (
    status = 'Pending'
    and exists (
      select 1 from public.events e
      where e.id = promoted_events.event_id
        and e.artist_id = auth.uid()::text
    )
  );
create policy "promoted_events artist read" on public.promoted_events
  for select
  using (
    exists (
      select 1 from public.events e
      where e.id = promoted_events.event_id
        and e.artist_id = auth.uid()::text
    )
  );
create policy "promoted_events admin manage" on public.promoted_events
  for all
  using (public.is_platform_admin(auth.uid()::text))
  with check (public.is_platform_admin(auth.uid()::text));
-- Grants (PostgREST)

grant select on public.events to anon, authenticated;
grant select on public.event_tickets to anon, authenticated;
grant select, insert on public.ticket_orders to authenticated;
grant select, insert on public.user_tickets to authenticated;
grant select, insert on public.promoted_events to authenticated;
grant select on public.promoted_events to anon;
-- Ask PostgREST to reload schema cache.
notify pgrst, 'reload schema';
