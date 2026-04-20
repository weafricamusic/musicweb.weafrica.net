-- Events + tickets + orders + promoted events (consumer + DJ/Artist dashboard)
--
-- Uses Firebase UID (text) for user_id fields.
-- RLS is intentionally NOT enabled in this migration (match existing project pattern).

create extension if not exists pgcrypto;
-- EVENTS
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  host_user_id text,
  host_name text not null,
  name text not null,
  poster_url text not null,
  country_code text not null default 'MW',
  city text,
  venue text,
  is_online boolean not null default false,
  starts_at timestamptz not null,
  ends_at timestamptz,
  description text not null default '',
  lineup text[] not null default '{}',
  status text not null default 'published',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists events_starts_at_idx on public.events (starts_at asc);
create index if not exists events_country_starts_at_idx on public.events (country_code, starts_at asc);
create index if not exists events_host_user_id_idx on public.events (host_user_id);
-- EVENT TICKETS
create table if not exists public.event_tickets (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  price_mwk integer not null default 0,
  is_vip boolean not null default false,
  capacity integer,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists event_tickets_event_id_idx on public.event_tickets (event_id);
-- TICKET ORDERS
create table if not exists public.ticket_orders (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  event_id uuid not null references public.events(id) on delete restrict,
  ticket_type_id uuid references public.event_tickets(id) on delete set null,
  quantity integer not null default 1,
  total_mwk integer not null default 0,
  payment_method text,
  payment_ref text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ticket_orders_user_id_idx on public.ticket_orders (user_id);
create index if not exists ticket_orders_event_id_idx on public.ticket_orders (event_id);
create index if not exists ticket_orders_created_at_idx on public.ticket_orders (created_at desc);
-- USER TICKETS (consumer wallet)
create table if not exists public.user_tickets (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.ticket_orders(id) on delete set null,
  user_id text not null,
  event_id uuid not null references public.events(id) on delete restrict,
  ticket_type_id uuid references public.event_tickets(id) on delete set null,
  quantity integer not null default 1,
  qr_payload text not null,
  status text not null default 'valid',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists user_tickets_user_id_idx on public.user_tickets (user_id);
create index if not exists user_tickets_event_id_idx on public.user_tickets (event_id);
create index if not exists user_tickets_status_idx on public.user_tickets (status);
-- PROMOTED EVENTS (paid boost)
create table if not exists public.promoted_events (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  paid_by_user_id text,
  placement_home boolean not null default true,
  placement_events_top boolean not null default true,
  placement_push boolean not null default false,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active',
  created_at timestamptz not null default now()
);
create index if not exists promoted_events_event_id_idx on public.promoted_events (event_id);
create index if not exists promoted_events_status_idx on public.promoted_events (status);
create index if not exists promoted_events_starts_at_idx on public.promoted_events (starts_at desc);
