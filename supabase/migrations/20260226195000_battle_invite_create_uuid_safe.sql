-- Fix: battle_invite_create battle_id type mismatch
--
-- Some environments have battle_id columns typed as uuid (e.g. older schema),
-- while newer migrations used text battle IDs.
--
-- The previous implementation generated a UUID but stored it in a TEXT variable
-- and inserted TEXT into battle_id, which fails when battle_id is uuid:
--   "column battle_id is of type uuid but expression is of type text"
--
-- This version generates a true uuid, inserts it into battle_id columns,
-- and still returns battle_id to clients as text.

create extension if not exists pgcrypto;

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
  bid uuid;
  bid_text text;
  ttl integer := coalesce(p_ttl_seconds, 60);
  exp timestamptz;
  from_uid_clean text := trim(coalesce(p_from_uid, ''));
  to_uid_clean text := trim(coalesce(p_to_uid, ''));
  pending_count integer;
  now_ts timestamptz := now();
begin
  if from_uid_clean = '' then
    raise exception 'from_uid_required';
  end if;
  if to_uid_clean = '' then
    raise exception 'to_uid_required';
  end if;
  if from_uid_clean = to_uid_clean then
    raise exception 'cannot_invite_self';
  end if;

  ttl := greatest(15, least(ttl, 300));

  -- Auto-expire stale pending invites for this sender (best-effort cleanup)
  update public.battle_invites
    set status = 'expired',
        responded_at = coalesce(responded_at, now_ts)
  where from_uid = from_uid_clean
    and status = 'pending'
    and public.battle_invites.expires_at <= now_ts
    and responded_at is null;

  -- Prevent duplicate pending invite to the same user
  if exists (
    select 1
    from public.battle_invites
    where from_uid = from_uid_clean
      and to_uid = to_uid_clean
      and status = 'pending'
      and public.battle_invites.expires_at > now_ts
  ) then
    raise exception 'invite_already_pending';
  end if;

  -- Prevent spam: cap active pending outbox invites
  select count(*)::int into pending_count
  from public.battle_invites
  where from_uid = from_uid_clean
    and status = 'pending'
    and public.battle_invites.expires_at > now_ts;

  if pending_count >= 3 then
    raise exception 'too_many_pending';
  end if;

  bid := gen_random_uuid();
  bid_text := bid::text;
  exp := now_ts + make_interval(secs => ttl);

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
    public._battle_channel_id(bid_text),
    'waiting',
    from_uid_clean,
    to_uid_clean,
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
    from_uid_clean,
    to_uid_clean,
    'pending',
    exp
  )
  returning id into invite_id;

  battle_id := bid_text;
  channel_id := public._battle_channel_id(bid_text);
  expires_at := exp;
  return next;
end;
$$;

revoke all on function public.battle_invite_create(text, text, integer) from public;
grant execute on function public.battle_invite_create(text, text, integer) to service_role;
