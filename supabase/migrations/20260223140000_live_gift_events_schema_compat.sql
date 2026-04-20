-- Live gifts schema compatibility (forward migration)
--
-- Some deployments created `public.live_gift_events` using an older/minimal schema
-- (e.g. stream_id/from_uid/to_uid/gift_type/coins) and later migrations added
-- RPCs + app code expecting `channel_id/from_user_id/to_host_id/gift_id/coin_cost`.
--
-- This migration:
-- - adds the newer columns (non-destructive)
-- - backfills best-effort values from legacy columns
-- - restores SELECT permission + a simple SELECT policy for anon/authenticated

alter table public.live_gift_events
  add column if not exists channel_id text,
  add column if not exists from_user_id text,
  add column if not exists sender_name text,
  add column if not exists to_host_id text,
  add column if not exists gift_id text,
  add column if not exists coin_cost bigint;

-- Best-effort backfill from legacy column names.
update public.live_gift_events
set
  from_user_id = coalesce(from_user_id, from_uid),
  to_host_id = coalesce(to_host_id, to_uid),
  gift_id = coalesce(gift_id, gift_type),
  coin_cost = coalesce(coin_cost, coins::bigint),
  sender_name = coalesce(sender_name, nullif(trim(meta->>'sender_name'), ''), 'User')
where
  from_user_id is null
  or to_host_id is null
  or gift_id is null
  or coin_cost is null
  or sender_name is null;

-- Some deployments also have a `live_id` column (often == channel_id).
-- Migration histories can diverge between projects, so guard this backfill.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'live_gift_events'
      and column_name = 'live_id'
  ) then
    execute $sql$
      update public.live_gift_events
      set channel_id = coalesce(channel_id, live_id)
      where channel_id is null and live_id is not null
    $sql$;
  end if;
end $$;

create index if not exists live_gift_events_channel_created_at_idx
  on public.live_gift_events (channel_id, created_at desc);

alter table public.live_gift_events enable row level security;

do $$
begin
  -- Safe default: allow clients to *read* gift events.
  -- (Inserts/updates should remain server-side via RPC/Edge Functions.)
  create policy "Public read live gifts" on public.live_gift_events
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

grant select on table public.live_gift_events to anon, authenticated;
