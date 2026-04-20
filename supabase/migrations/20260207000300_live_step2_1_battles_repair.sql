-- STEP 2.1 (repair) — Ensure live_battles schema matches the app
--
-- Some environments may already have a legacy `live_battles` table without
-- the `battle_id` primary key column. The Flutter app + Edge functions expect:
-- - battle_id text primary key
-- - channel_id unique
-- - host slots + ready flags
-- - optional host Agora UIDs
--
-- This migration is defensive:
-- - If `live_battles` is missing `battle_id`, it drops & recreates the table.
-- - Otherwise it leaves data intact and only adds missing columns.

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'live_battles'
  ) then
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'live_battles'
        and column_name = 'battle_id'
    ) then
      drop table public.live_battles cascade;
    end if;
  end if;
end $$;
create table if not exists public.live_battles (
  battle_id text primary key,
  channel_id text not null unique,
  status text not null default 'waiting' check (status in ('waiting','live','ended')),

  host_a_id text,
  host_b_id text,

  host_a_agora_uid bigint,
  host_b_agora_uid bigint,

  host_a_ready boolean not null default false,
  host_b_ready boolean not null default false,

  started_at timestamptz,
  ended_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- If table existed but some columns are missing, add them.
alter table public.live_battles
  add column if not exists channel_id text,
  add column if not exists status text,
  add column if not exists host_a_id text,
  add column if not exists host_b_id text,
  add column if not exists host_a_agora_uid bigint,
  add column if not exists host_b_agora_uid bigint,
  add column if not exists host_a_ready boolean,
  add column if not exists host_b_ready boolean,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;
-- Backfill defaults for newly added columns where needed.
update public.live_battles
set
  channel_id = coalesce(channel_id, 'weafrica_battle_' || battle_id),
  status = coalesce(status, 'waiting'),
  host_a_ready = coalesce(host_a_ready, false),
  host_b_ready = coalesce(host_b_ready, false),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  channel_id is null
  or status is null
  or host_a_ready is null
  or host_b_ready is null
  or created_at is null
  or updated_at is null;
create or replace function public._touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists trg_live_battles_touch on public.live_battles;
create trigger trg_live_battles_touch
before update on public.live_battles
for each row execute function public._touch_updated_at();
alter table public.live_battles enable row level security;
drop policy if exists "live_battles_select_all" on public.live_battles;
create policy "live_battles_select_all"
  on public.live_battles
  for select
  to anon, authenticated
  using (true);
-- Ensure latest host-claiming function exists (Agora UID aware).
drop function if exists public.battle_claim_host(text, text, text);
drop function if exists public.battle_claim_host(text, text, text, bigint);
create or replace function public.battle_claim_host(
  p_battle_id text,
  p_channel_id text,
  p_user_id text,
  p_agora_uid bigint
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  au bigint := nullif(p_agora_uid, 0);
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_channel_id is null or length(trim(p_channel_id)) = 0 then
    raise exception 'channel_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  insert into public.live_battles(battle_id, channel_id)
  values (trim(p_battle_id), trim(p_channel_id))
  on conflict (battle_id) do nothing;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if b.host_a_id = trim(p_user_id) then
    update public.live_battles
      set host_a_agora_uid = coalesce(au, host_a_agora_uid)
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  if b.host_b_id = trim(p_user_id) then
    update public.live_battles
      set host_b_agora_uid = coalesce(au, host_b_agora_uid)
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  if b.host_a_id is null then
    update public.live_battles
      set host_a_id = trim(p_user_id),
          host_a_agora_uid = au
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  if b.host_b_id is null then
    update public.live_battles
      set host_b_id = trim(p_user_id),
          host_b_agora_uid = au
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  raise exception 'battle_full';
end;
$$;
revoke all on function public.battle_claim_host(text, text, text, bigint) from public;
grant execute on function public.battle_claim_host(text, text, text, bigint) to service_role;
-- Ensure ready function exists.
drop function if exists public.battle_set_ready(text, text, boolean);
create or replace function public.battle_set_ready(
  p_battle_id text,
  p_user_id text,
  p_ready boolean
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  ready boolean := coalesce(p_ready, true);
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if not found then
    raise exception 'battle_not_found';
  end if;

  if b.host_a_id = trim(p_user_id) then
    update public.live_battles
      set host_a_ready = ready
    where battle_id = trim(p_battle_id)
    returning * into b;
  elsif b.host_b_id = trim(p_user_id) then
    update public.live_battles
      set host_b_ready = ready
    where battle_id = trim(p_battle_id)
    returning * into b;
  else
    raise exception 'not_a_host';
  end if;

  if b.status = 'waiting' and b.host_a_ready and b.host_b_ready then
    update public.live_battles
      set status = 'live', started_at = coalesce(started_at, now())
    where battle_id = trim(p_battle_id)
    returning * into b;
  end if;

  return b;
end;
$$;
revoke all on function public.battle_set_ready(text, text, boolean) from public;
grant execute on function public.battle_set_ready(text, text, boolean) to service_role;
