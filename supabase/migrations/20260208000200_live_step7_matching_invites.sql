-- STEP 7 — Battle matching & invites
--
-- Two modes:
-- A) Direct invite: battle_invites (pending/accepted/declined/expired)
-- B) Quick match: battle_queue + battle_match_events
--
-- All writes are intended to happen via Edge Function using service_role.

-- 1) Invite table

create table if not exists public.battle_invites (
  id uuid primary key default gen_random_uuid(),
  battle_id text not null references public.live_battles(battle_id) on delete cascade,
  from_uid text not null,
  to_uid text not null,
  status text not null default 'pending' check (status in ('pending','accepted','declined','expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz
);

create index if not exists battle_invites_to_status_created_idx
  on public.battle_invites (to_uid, status, created_at desc);

create index if not exists battle_invites_from_status_created_idx
  on public.battle_invites (from_uid, status, created_at desc);

alter table public.battle_invites enable row level security;

-- Reads are handled via Edge Function; keep public select off by default.
revoke all on table public.battle_invites from anon, authenticated;

-- 2) Quick match queue

create table if not exists public.battle_queue (
  uid text primary key,
  role text not null check (role in ('artist','dj')),
  country text,
  joined_at timestamptz not null default now()
);

create index if not exists battle_queue_role_country_joined_idx
  on public.battle_queue (role, country, joined_at);

alter table public.battle_queue enable row level security;
revoke all on table public.battle_queue from anon, authenticated;

-- 3) Match events (so the "other" user can poll and still get the battle)

create table if not exists public.battle_match_events (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  battle_id text not null references public.live_battles(battle_id) on delete cascade,
  created_at timestamptz not null default now(),
  consumed_at timestamptz
);

create index if not exists battle_match_events_user_pending_idx
  on public.battle_match_events (user_id, created_at desc)
  where consumed_at is null;

alter table public.battle_match_events enable row level security;
revoke all on table public.battle_match_events from anon, authenticated;

-- 4) Helpers

create or replace function public._battle_channel_id(p_battle_id text)
returns text
language sql
immutable
as $$
  select 'weafrica_battle_' || trim(p_battle_id)
$$;

-- 5) Direct invite: create a battle + invite

create or replace function public.battle_invite_create(
  p_from_uid text,
  p_to_uid text,
  p_ttl_seconds integer default 60
)
returns table (invite_id uuid, battle_id text, channel_id text, expires_at timestamptz)
language plpgsql
security definer
as $$
declare
  bid text;
  ttl integer := coalesce(p_ttl_seconds, 60);
  exp timestamptz;
begin
  if p_from_uid is null or length(trim(p_from_uid)) = 0 then
    raise exception 'from_uid_required';
  end if;
  if p_to_uid is null or length(trim(p_to_uid)) = 0 then
    raise exception 'to_uid_required';
  end if;
  if trim(p_from_uid) = trim(p_to_uid) then
    raise exception 'cannot_invite_self';
  end if;

  ttl := greatest(15, least(ttl, 300));
  bid := gen_random_uuid()::text;
  exp := now() + make_interval(secs => ttl);

  insert into public.live_battles(
    battle_id,
    channel_id,
    status,
    host_a_id,
    host_b_id,
    host_a_ready,
    host_b_ready,
    started_at,
    ended_at,
    ends_at
  ) values (
    bid,
    public._battle_channel_id(bid),
    'waiting',
    trim(p_from_uid),
    trim(p_to_uid),
    false,
    false,
    null,
    null,
    null
  );

  insert into public.battle_invites(
    battle_id,
    from_uid,
    to_uid,
    status,
    expires_at
  ) values (
    bid,
    trim(p_from_uid),
    trim(p_to_uid),
    'pending',
    exp
  )
  returning id into invite_id;

  battle_id := bid;
  channel_id := public._battle_channel_id(bid);
  expires_at := exp;
  return next;
end;
$$;

-- 6) Invite response

create or replace function public.battle_invite_respond(
  p_invite_id uuid,
  p_to_uid text,
  p_action text
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  inv public.battle_invites;
  b public.live_battles;
  action text := lower(coalesce(trim(p_action), ''));
  now_ts timestamptz := now();
begin
  if p_invite_id is null then
    raise exception 'invite_id_required';
  end if;
  if p_to_uid is null or length(trim(p_to_uid)) = 0 then
    raise exception 'to_uid_required';
  end if;
  if action not in ('accept','decline') then
    raise exception 'invalid_action';
  end if;

  select * into inv
  from public.battle_invites
  where id = p_invite_id
  for update;

  if not found then
    raise exception 'invite_not_found';
  end if;

  if inv.to_uid <> trim(p_to_uid) then
    raise exception 'not_invited_user';
  end if;

  if inv.status <> 'pending' then
    raise exception 'invite_not_pending';
  end if;

  if now_ts >= inv.expires_at then
    update public.battle_invites
      set status = 'expired',
          responded_at = coalesce(responded_at, now_ts)
    where id = p_invite_id;
    raise exception 'invite_expired';
  end if;

  if action = 'decline' then
    update public.battle_invites
      set status = 'declined',
          responded_at = now_ts
    where id = p_invite_id;
  else
    update public.battle_invites
      set status = 'accepted',
          responded_at = now_ts
    where id = p_invite_id;
  end if;

  select * into b
  from public.live_battles
  where battle_id = inv.battle_id;

  if not found then
    raise exception 'battle_not_found';
  end if;

  return b;
end;
$$;

-- 7) Quick match: join queue + attempt match
-- Returns NULL if still queued.

create or replace function public.battle_quick_match_join(
  p_uid text,
  p_role text,
  p_country text default null
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  v_uid text := trim(coalesce(p_uid, ''));
  v_role text := lower(trim(coalesce(p_role, '')));
  v_country text := nullif(lower(trim(coalesce(p_country, ''))), '');
  other_uid text;
  battle public.live_battles;
  bid text;
begin
  if v_uid = '' then
    raise exception 'user_id_required';
  end if;
  if v_role not in ('artist','dj') then
    raise exception 'invalid_role';
  end if;

  -- If a match event already exists for this user, consume and return its battle.
  select b.* into battle
  from public.battle_match_events e
  join public.live_battles b on b.battle_id = e.battle_id
  where e.user_id = v_uid
    and e.consumed_at is null
  order by e.created_at desc
  limit 1;

  if found then
    update public.battle_match_events
      set consumed_at = now()
    where id in (
      select id
      from public.battle_match_events
      where user_id = v_uid and consumed_at is null
      order by created_at desc
      limit 1
    );
    return battle;
  end if;

  -- Upsert queue row.
  insert into public.battle_queue(uid, role, country, joined_at)
  values (v_uid, v_role, v_country, now())
  on conflict (uid)
  do update set role = excluded.role,
                country = excluded.country,
                joined_at = excluded.joined_at;

  -- Prefer same-country match, else any.
  other_uid := null;
  if v_country is not null then
    select q.uid into other_uid
    from public.battle_queue q
    where q.role = v_role
      and q.uid <> v_uid
      and q.country = v_country
    order by q.joined_at asc
    limit 1
    for update skip locked;
  end if;

  if other_uid is null then
    select q.uid into other_uid
    from public.battle_queue q
    where q.role = v_role
      and q.uid <> v_uid
    order by q.joined_at asc
    limit 1
    for update skip locked;
  end if;

  if other_uid is null then
    return null;
  end if;

  -- Remove both from queue.
  delete from public.battle_queue where uid in (v_uid, other_uid);

  -- Create battle.
  bid := gen_random_uuid()::text;

  insert into public.live_battles(
    battle_id,
    channel_id,
    status,
    host_a_id,
    host_b_id,
    host_a_ready,
    host_b_ready
  ) values (
    bid,
    public._battle_channel_id(bid),
    'waiting',
    v_uid,
    other_uid,
    false,
    false
  )
  returning * into battle;

  -- Emit match events for both users.
  insert into public.battle_match_events(user_id, battle_id)
  values (v_uid, bid), (other_uid, bid);

  -- Consume the caller's event immediately.
  update public.battle_match_events
    set consumed_at = now()
  where user_id = v_uid and battle_id = bid and consumed_at is null;

  return battle;
end;
$$;

create or replace function public.battle_quick_match_cancel(
  p_uid text
)
returns void
language plpgsql
security definer
as $$
begin
  if p_uid is null or length(trim(p_uid)) = 0 then
    raise exception 'user_id_required';
  end if;
  delete from public.battle_queue where uid = trim(p_uid);
end;
$$;

create or replace function public.battle_quick_match_poll(
  p_uid text
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  v_uid text := trim(coalesce(p_uid, ''));
  ev_id uuid;
  ev_battle_id text;
  b public.live_battles;
begin
  if v_uid = '' then
    raise exception 'user_id_required';
  end if;

  select e.id, e.battle_id
    into ev_id, ev_battle_id
  from public.battle_match_events e
  where e.user_id = v_uid
    and e.consumed_at is null
  order by e.created_at desc
  limit 1
  for update;

  if not found then
    return null;
  end if;

  update public.battle_match_events
    set consumed_at = now()
  where id = ev_id;

  select * into b
  from public.live_battles
  where battle_id = ev_battle_id;

  return b;
end;
$$;

-- Permissions

revoke all on function public._battle_channel_id(text) from public;
revoke all on function public.battle_invite_create(text, text, integer) from public;
revoke all on function public.battle_invite_respond(uuid, text, text) from public;
revoke all on function public.battle_quick_match_join(text, text, text) from public;
revoke all on function public.battle_quick_match_cancel(text) from public;
revoke all on function public.battle_quick_match_poll(text) from public;

grant execute on function public._battle_channel_id(text) to service_role;
grant execute on function public.battle_invite_create(text, text, integer) to service_role;
grant execute on function public.battle_invite_respond(uuid, text, text) to service_role;
grant execute on function public.battle_quick_match_join(text, text, text) to service_role;
grant execute on function public.battle_quick_match_cancel(text) to service_role;
grant execute on function public.battle_quick_match_poll(text) to service_role;
