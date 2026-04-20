-- STEP 1.6 (ARTIST EARNINGS)
-- Adds an artist wallet and credits it atomically during send_gift.

-- ARTIST WALLET
create table if not exists public.artist_wallets (
  artist_id text primary key,
  earned_coins bigint not null default 0,
  withdrawable_coins bigint not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.artist_wallets enable row level security;
-- NOTE: Client uses Supabase anon for realtime; keep reads public for now.
-- Tighten later once Firebase->Supabase auth is unified.
do $$
begin
  create policy "Public read artist wallets" on public.artist_wallets
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;
grant select on table public.artist_wallets to anon, authenticated;
-- Ensure gift events contain a live_id (for future analytics/battles).
-- We treat live_id as an app-level identifier (can equal channel_id).
alter table public.live_gift_events
  add column if not exists live_id text;
-- Replace send_gift to also credit the artist wallet atomically.
create or replace function public.send_gift(
  p_live_id text,
  p_channel_id text,
  p_from_user_id text,
  p_to_host_id text,
  p_gift_id text,
  p_coin_cost bigint,
  p_sender_name text
)
returns table (new_balance bigint, event_id uuid, artist_earned_coins bigint)
language plpgsql
as $$
declare
  current_balance bigint;
  normalized_name text;
  new_artist_earned bigint;
begin
  if p_coin_cost is null or p_coin_cost <= 0 then
    raise exception 'invalid_coin_cost' using errcode = 'P0001';
  end if;

  -- Viewer wallet row.
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

  -- Artist wallet row.
  insert into public.artist_wallets(artist_id, earned_coins, withdrawable_coins)
  values (p_to_host_id, 0, 0)
  on conflict (artist_id) do nothing;

  update public.artist_wallets
    set earned_coins = earned_coins + p_coin_cost,
        withdrawable_coins = withdrawable_coins + p_coin_cost,
        updated_at = now()
    where artist_id = p_to_host_id
    returning earned_coins into new_artist_earned;

  normalized_name := coalesce(nullif(trim(p_sender_name), ''), 'User');

  insert into public.live_gift_events(
    live_id,
    channel_id,
    from_user_id,
    sender_name,
    to_host_id,
    gift_id,
    coin_cost
  ) values (
    nullif(trim(p_live_id), ''),
    p_channel_id,
    p_from_user_id,
    normalized_name,
    p_to_host_id,
    p_gift_id,
    p_coin_cost
  ) returning id into event_id;

  artist_earned_coins := new_artist_earned;
  return next;
end;
$$;
