-- STEP 1.5 (VIEWER COINS + WALLET + GIFTS)
-- Backend source of truth.
-- - wallets: per Firebase user_id (text)
-- - live_gift_events: realtime gift events for viewers + host
-- - send_gift(): atomic coin deduction + event insert

-- VIEWER WALLET
create table if not exists public.wallets (
  user_id text primary key,
  coin_balance bigint not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.wallets enable row level security;
-- LIVE GIFT EVENTS (realtime)
create table if not exists public.live_gift_events (
  id uuid primary key default gen_random_uuid(),
  channel_id text not null,
  from_user_id text not null,
  sender_name text not null,
  to_host_id text not null,
  gift_id text not null,
  coin_cost bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists live_gift_events_channel_created_at_idx
  on public.live_gift_events (channel_id, created_at desc);
alter table public.live_gift_events enable row level security;
do $$
begin
  create policy "Public read live gifts" on public.live_gift_events
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;
-- Atomic gift transaction: deduct coins + log event.
-- NOTE: do NOT grant execute to anon/authenticated.
create or replace function public.send_gift(
  p_channel_id text,
  p_from_user_id text,
  p_to_host_id text,
  p_gift_id text,
  p_coin_cost bigint,
  p_sender_name text
)
returns table (new_balance bigint, event_id uuid)
language plpgsql
as $$
declare
  current_balance bigint;
  normalized_name text;
begin
  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  insert into public.wallets(user_id, coin_balance)
  values (p_from_user_id, 0)
  on conflict (user_id) do nothing;

  select coin_balance
    into current_balance
    from public.wallets
    where user_id = p_from_user_id
    for update;

  if current_balance < p_coin_cost then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;

  update public.wallets
    set coin_balance = coin_balance - p_coin_cost,
        updated_at = now()
    where user_id = p_from_user_id
    returning coin_balance into new_balance;

  normalized_name := coalesce(nullif(trim(p_sender_name), ''), 'User');

  insert into public.live_gift_events(
    channel_id,
    from_user_id,
    sender_name,
    to_host_id,
    gift_id,
    coin_cost
  ) values (
    p_channel_id,
    p_from_user_id,
    normalized_name,
    p_to_host_id,
    p_gift_id,
    p_coin_cost
  ) returning id into event_id;

  return next;
end;
$$;
