-- Live Battle schema (Supabase)
-- Apply in Supabase SQL editor (Database -> SQL).
-- NOTE: For realtime updates, enable Realtime on the tables in Supabase Dashboard.

create table if not exists public.live_battles (
  id uuid primary key default gen_random_uuid(),
  channel text not null,
  title text,
  created_at timestamptz not null default now()
);

do $$
begin
  create unique index live_battles_channel_unique on public.live_battles (channel);
exception
  when duplicate_object then null;
end $$;

create table if not exists public.live_battle_state (
  battle_id uuid primary key references public.live_battles(id) on delete cascade,
  artist1_coins integer not null default 0,
  artist2_coins integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.live_battle_coin_balances (
  user_id text primary key,
  coins integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.live_battle_gifts (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.live_battles(id) on delete cascade,
  user_id text not null,
  artist integer not null check (artist in (1,2)),
  coins integer not null check (coins > 0),
  gift_name text,
  created_at timestamptz not null default now()
);

create index if not exists live_battle_gifts_battle_id_idx on public.live_battle_gifts (battle_id);
create index if not exists live_battle_gifts_user_id_idx on public.live_battle_gifts (user_id);
create index if not exists live_battle_gifts_created_at_idx on public.live_battle_gifts (created_at desc);

-- Atomic helper for sending gifts + updating state + deducting coins.
create or replace function public.live_battle_send_gift(
  p_channel text,
  p_user_id text,
  p_artist integer,
  p_coins integer,
  p_gift_name text default null
) returns void
language plpgsql
as $$
declare
  v_battle_id uuid;
begin
  if p_channel is null or length(trim(p_channel)) = 0 then
    raise exception 'channel required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id required';
  end if;
  if p_artist not in (1,2) then
    raise exception 'artist must be 1 or 2';
  end if;
  if p_coins is null or p_coins <= 0 then
    raise exception 'coins must be > 0';
  end if;

  insert into public.live_battles(channel)
  values (p_channel)
  on conflict (channel) do update set channel = excluded.channel
  returning id into v_battle_id;

  insert into public.live_battle_state(battle_id)
  values (v_battle_id)
  on conflict (battle_id) do nothing;

  insert into public.live_battle_coin_balances(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  -- Deduct user coins (best-effort: prototype semantics)
  update public.live_battle_coin_balances
  set coins = greatest(coins - p_coins, 0),
      updated_at = now()
  where user_id = p_user_id;

  insert into public.live_battle_gifts(battle_id, user_id, artist, coins, gift_name)
  values (v_battle_id, p_user_id, p_artist, p_coins, p_gift_name);

  update public.live_battle_state
  set artist1_coins = artist1_coins + case when p_artist = 1 then p_coins else 0 end,
      artist2_coins = artist2_coins + case when p_artist = 2 then p_coins else 0 end,
      updated_at = now()
  where battle_id = v_battle_id;
end;
$$;

create or replace function public.live_battle_add_coins(
  p_user_id text,
  p_delta integer
) returns void
language plpgsql
as $$
begin
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id required';
  end if;
  if p_delta is null or p_delta <= 0 then
    raise exception 'delta must be > 0';
  end if;

  insert into public.live_battle_coin_balances(user_id, coins)
  values (p_user_id, p_delta)
  on conflict (user_id)
  do update set coins = public.live_battle_coin_balances.coins + excluded.coins,
               updated_at = now();
end;
$$;

-- RLS (prototype): open read/write for anon/authenticated.
-- For production, lock this down and verify Firebase ID tokens server-side.

alter table public.live_battles enable row level security;
drop policy if exists "Public read live_battles" on public.live_battles;
create policy "Public read live_battles" on public.live_battles
  for select to anon, authenticated
  using (true);

drop policy if exists "Public write live_battles" on public.live_battles;
create policy "Public write live_battles" on public.live_battles
  for insert to anon, authenticated
  with check (channel is not null and length(channel) > 0);

drop policy if exists "Public update live_battles" on public.live_battles;
create policy "Public update live_battles" on public.live_battles
  for update to anon, authenticated
  using (true);

alter table public.live_battle_state enable row level security;
drop policy if exists "Public read live_battle_state" on public.live_battle_state;
create policy "Public read live_battle_state" on public.live_battle_state
  for select to anon, authenticated
  using (true);

drop policy if exists "Public write live_battle_state" on public.live_battle_state;
create policy "Public write live_battle_state" on public.live_battle_state
  for insert to anon, authenticated
  with check (true);

drop policy if exists "Public update live_battle_state" on public.live_battle_state;
create policy "Public update live_battle_state" on public.live_battle_state
  for update to anon, authenticated
  using (true);

alter table public.live_battle_coin_balances enable row level security;
drop policy if exists "Public read live_battle_coin_balances" on public.live_battle_coin_balances;
create policy "Public read live_battle_coin_balances" on public.live_battle_coin_balances
  for select to anon, authenticated
  using (true);

drop policy if exists "Public write live_battle_coin_balances" on public.live_battle_coin_balances;
create policy "Public write live_battle_coin_balances" on public.live_battle_coin_balances
  for insert to anon, authenticated
  with check (user_id is not null and length(user_id) > 0);

drop policy if exists "Public update live_battle_coin_balances" on public.live_battle_coin_balances;
create policy "Public update live_battle_coin_balances" on public.live_battle_coin_balances
  for update to anon, authenticated
  using (true);

alter table public.live_battle_gifts enable row level security;
drop policy if exists "Public read live_battle_gifts" on public.live_battle_gifts;
create policy "Public read live_battle_gifts" on public.live_battle_gifts
  for select to anon, authenticated
  using (true);

drop policy if exists "Public write live_battle_gifts" on public.live_battle_gifts;
create policy "Public write live_battle_gifts" on public.live_battle_gifts
  for insert to anon, authenticated
  with check (user_id is not null and length(user_id) > 0);
