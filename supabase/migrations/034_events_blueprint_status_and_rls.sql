-- Blueprint alignment: Events status workflow + stricter RLS + promotion statuses
--
-- Canonical statuses (Title Case):
--   Events: Draft -> Submitted -> Published | Rejected | Completed
--   Promotions: Pending | Approved | Active | Rejected | Completed
--
-- This migration is additive/idempotent and safe to run on environments where 030/031/032/033 exist.

create extension if not exists pgcrypto;
-- 1) Normalize existing event statuses (best-effort)
do $$
begin
  if to_regclass('public.events') is not null then
    begin
      execute $sql$
        update public.events
        set status = case
          when status is null then 'Draft'
          when lower(status) in ('draft') then 'Draft'
          when lower(status) in ('submitted','pending_review','pendingreview','pending','in_review','review') then 'Submitted'
          when lower(status) in ('published','publish','approved','active') then 'Published'
          when lower(status) in ('rejected') then 'Rejected'
          when lower(status) in ('completed') then 'Completed'
          else status
        end
      $sql$;
    exception when others then
      null;
    end;

    -- Moderation columns (harmless if already present)
    begin execute 'alter table public.events add column if not exists admin_notes text'; exception when others then null; end;
    begin execute 'alter table public.events add column if not exists reviewed_by text'; exception when others then null; end;
    begin execute 'alter table public.events add column if not exists reviewed_at timestamptz'; exception when others then null; end;

    -- Default
    begin
      execute 'alter table public.events alter column status set default ''Draft''';
    exception when others then
      null;
    end;

    -- Replace status check constraint
    begin
      execute 'alter table public.events drop constraint if exists events_status_check';
    exception when undefined_object then
      null;
    end;

    begin
      execute $sql$
        alter table public.events
        add constraint events_status_check
        check (status in ('Draft','Submitted','Published','Rejected','Completed'))
      $sql$;
    exception when others then
      -- Keep table usable if existing data violates constraint.
      null;
    end;
  end if;
end
$$;
-- 2) Normalize promotion statuses + constraint (best-effort)
do $$
begin
  if to_regclass('public.promoted_events') is not null then
    begin
      execute $sql$
        update public.promoted_events
        set status = case
          when status is null then 'Pending'
          when lower(status) in ('pending','requested') then 'Pending'
          when lower(status) in ('approved') then 'Approved'
          when lower(status) in ('active') then 'Active'
          when lower(status) in ('rejected','declined') then 'Rejected'
          when lower(status) in ('completed','ended','stopped') then 'Completed'
          else status
        end
      $sql$;
    exception when others then
      null;
    end;

    begin
      execute 'alter table public.promoted_events drop constraint if exists promoted_events_status_check';
    exception when undefined_object then
      null;
    end;

    begin
      execute $sql$
        alter table public.promoted_events
        add constraint promoted_events_status_check
        check (status in ('Pending','Approved','Active','Rejected','Completed'))
      $sql$;
    exception when others then
      null;
    end;
  end if;
end
$$;
-- 3) RLS tightening: hosts can’t self-publish; public read only Published
--
-- NOTE: 031 created broad "artist manage" policies. Here we replace them with scoped policies.

-- EVENTS
alter table public.events enable row level security;
drop policy if exists "events public read" on public.events;
drop policy if exists "events artist manage" on public.events;
drop policy if exists "events artist read" on public.events;
drop policy if exists "events artist insert" on public.events;
drop policy if exists "events artist update" on public.events;
drop policy if exists "events artist delete" on public.events;
create policy "events public read" on public.events
  for select
  using (status = 'Published');
create policy "events artist read" on public.events
  for select
  using (artist_id = auth.uid()::text);
create policy "events artist insert" on public.events
  for insert
  with check (
    artist_id = auth.uid()::text
    and status in ('Draft','Submitted','Rejected')
  );
create policy "events artist update" on public.events
  for update
  using (
    artist_id = auth.uid()::text
    and status in ('Draft','Submitted','Rejected')
  )
  with check (
    artist_id = auth.uid()::text
    and status in ('Draft','Submitted','Rejected')
  );
create policy "events artist delete" on public.events
  for delete
  using (
    artist_id = auth.uid()::text
    and status in ('Draft','Rejected')
  );
-- EVENT_TICKETS
alter table public.event_tickets enable row level security;
drop policy if exists "event_tickets public read" on public.event_tickets;
drop policy if exists "event_tickets artist manage" on public.event_tickets;
drop policy if exists "event_tickets artist read" on public.event_tickets;
drop policy if exists "event_tickets artist insert" on public.event_tickets;
drop policy if exists "event_tickets artist update" on public.event_tickets;
drop policy if exists "event_tickets artist delete" on public.event_tickets;
create policy "event_tickets public read" on public.event_tickets
  for select
  using (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.status = 'Published'
    )
  );
create policy "event_tickets artist read" on public.event_tickets
  for select
  using (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
    )
  );
create policy "event_tickets artist insert" on public.event_tickets
  for insert
  with check (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
        and e.status in ('Draft','Submitted','Rejected')
    )
  );
create policy "event_tickets artist update" on public.event_tickets
  for update
  using (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
        and e.status in ('Draft','Submitted','Rejected')
    )
  )
  with check (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
        and e.status in ('Draft','Submitted','Rejected')
    )
  );
create policy "event_tickets artist delete" on public.event_tickets
  for delete
  using (
    exists (
      select 1 from public.events e
      where e.id = event_tickets.event_id
        and e.artist_id = auth.uid()::text
        and e.status in ('Draft','Rejected')
    )
  );
-- PROMOTED_EVENTS
alter table public.promoted_events enable row level security;
drop policy if exists "promoted_events public read" on public.promoted_events;
drop policy if exists "promoted_events artist request" on public.promoted_events;
create policy "promoted_events public read" on public.promoted_events
  for select
  using (
    status = 'Active'
    and now() >= start_date
    and (end_date is null or now() <= end_date)
  );
create policy "promoted_events artist request" on public.promoted_events
  for insert
  with check (
    status = 'Pending'
    and exists (
      select 1 from public.events e
      where e.id = promoted_events.event_id
        and e.artist_id = auth.uid()::text
        and e.status in ('Draft','Submitted','Rejected')
    )
  );
