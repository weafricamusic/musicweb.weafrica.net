-- Creator Journey + Push Queue (Day 0-8+ lifecycle)
--
-- This provides:
-- - Per-user journey state (derived from events)
-- - Event log (deduped)
-- - Push queue (scheduled, deduped)
-- - RPC to claim due pushes atomically (FOR UPDATE SKIP LOCKED)

create table if not exists public.creator_journey_state (
  user_uid text primary key,
  flow_version integer not null default 1,
  started_at timestamptz not null default now(),
  role text,
  plan_id text,
  subscription_status text,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  first_upload_at timestamptz,
  first_live_at timestamptz,
  first_battle_at timestamptz,
  last_event_at timestamptz,
  last_push_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists creator_journey_state_updated_at_idx
  on public.creator_journey_state (updated_at desc);

create table if not exists public.creator_journey_events (
  id uuid primary key default gen_random_uuid(),
  user_uid text not null,
  event_type text not null,
  event_key text not null default '',
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists creator_journey_events_user_uid_idx
  on public.creator_journey_events (user_uid, occurred_at desc);

create unique index if not exists creator_journey_events_dedupe_idx
  on public.creator_journey_events (user_uid, event_type, event_key)
  where event_key <> '';

create table if not exists public.creator_journey_push_queue (
  id uuid primary key default gen_random_uuid(),
  user_uid text not null,
  template_key text not null,
  dedupe_key text not null,
  send_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','sent','canceled','failed')),
  payload jsonb not null default '{}'::jsonb,
  locked_at timestamptz,
  locked_by text,
  sent_at timestamptz,
  fail_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists creator_journey_push_queue_due_idx
  on public.creator_journey_push_queue (status, send_at asc)
  where status = 'pending';

create unique index if not exists creator_journey_push_queue_dedupe_idx
  on public.creator_journey_push_queue (user_uid, dedupe_key);

alter table public.creator_journey_state enable row level security;
alter table public.creator_journey_events enable row level security;
alter table public.creator_journey_push_queue enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'creator_journey_state'
      and policyname = 'deny_all_creator_journey_state'
  ) then
    create policy deny_all_creator_journey_state
      on public.creator_journey_state
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'creator_journey_events'
      and policyname = 'deny_all_creator_journey_events'
  ) then
    create policy deny_all_creator_journey_events
      on public.creator_journey_events
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'creator_journey_push_queue'
      and policyname = 'deny_all_creator_journey_push_queue'
  ) then
    create policy deny_all_creator_journey_push_queue
      on public.creator_journey_push_queue
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Atomic claim of due pushes (service_role only)
create or replace function public.creator_journey_claim_due_pushes(
  p_max integer default 50,
  p_lock_minutes integer default 15
)
returns table (
  id uuid,
  user_uid text,
  template_key text,
  dedupe_key text,
  send_at timestamptz,
  payload jsonb
)
language plpgsql
security definer
as $$
begin
  return query
  with due as (
    select q.id
    from public.creator_journey_push_queue q
    where q.status = 'pending'
      and q.send_at <= now()
      and (q.locked_at is null or q.locked_at < now() - make_interval(mins => greatest(p_lock_minutes, 1)))
    order by q.send_at asc
    limit greatest(p_max, 1)
    for update skip locked
  )
  update public.creator_journey_push_queue q
    set locked_at = now(),
        locked_by = 'journey_dispatch',
        updated_at = now()
  from due
  where q.id = due.id
  returning q.id, q.user_uid, q.template_key, q.dedupe_key, q.send_at, q.payload;
end;
$$;

revoke all on function public.creator_journey_claim_due_pushes(integer, integer) from public;
grant execute on function public.creator_journey_claim_due_pushes(integer, integer) to service_role;
