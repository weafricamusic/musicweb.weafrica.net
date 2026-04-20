-- Moderation + Safety core tables for admin dashboard.
-- Service-role bypasses RLS; normal clients are denied by default.

-- 1) Reports (append-only by convention; do not delete)
create table if not exists public.reports (
  id bigserial primary key,
  content_type text not null check (content_type in ('song','video','live','comment','profile')),
  content_id text not null,
  reason text not null check (reason in (
    'copyright_infringement',
    'nudity_sexual_content',
    'hate_violence',
    'spam_scam',
    'harassment',
    'fake_account',
    'other'
  )),
  reporter_id text,
  reporter_message text,
  status text not null default 'open' check (status in ('open','resolved','dismissed')),

  -- Optional owner info (helps build the "Reported Users" page).
  content_owner_type text check (content_owner_type in ('user','artist','dj')),
  content_owner_id text,

  resolved_at timestamptz,
  resolved_by_email text,
  resolution_action text check (resolution_action in (
    'dismiss',
    'remove_content',
    'warn_user',
    'block_user',
    'end_live',
    'mute_audio'
  )),
  resolution_note text,

  created_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);
create index if not exists reports_status_idx on public.reports (status);
create index if not exists reports_created_at_idx on public.reports (created_at desc);
create index if not exists reports_content_idx on public.reports (content_type, content_id);
create index if not exists reports_owner_idx on public.reports (content_owner_type, content_owner_id);
alter table public.reports enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and policyname = 'deny_all_reports'
  ) then
    create policy deny_all_reports
      on public.reports
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- 2) Moderation actions (legal/audit shield)
create table if not exists public.moderation_actions (
  id bigserial primary key,
  report_id bigint references public.reports(id),
  admin_email text,
  action text not null check (action in (
    'DISMISS_REPORT',
    'REMOVE_CONTENT',
    'WARN_USER',
    'BLOCK_USER',
    'END_LIVE',
    'MUTE_AUDIO'
  )),
  reason text,
  target_type text,
  target_id text,
  created_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);
create index if not exists moderation_actions_created_at_idx on public.moderation_actions (created_at desc);
create index if not exists moderation_actions_action_idx on public.moderation_actions (action);
create index if not exists moderation_actions_target_idx on public.moderation_actions (target_type, target_id);
create index if not exists moderation_actions_report_idx on public.moderation_actions (report_id);
alter table public.moderation_actions enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'moderation_actions'
      and policyname = 'deny_all_moderation_actions'
  ) then
    create policy deny_all_moderation_actions
      on public.moderation_actions
      for all
      using (false)
      with check (false);
  end if;
end $$;
-- 3) RPC helpers
create or replace function public.moderation_top_summary()
returns table (
  open_reports bigint,
  resolved_today bigint,
  blocked_content_today bigint,
  blocked_users_today bigint,
  live_open_reports bigint
)
language sql
stable
as $$
  with
    open_reports as (
      select count(*)::bigint as c
      from public.reports
      where status = 'open'
    ),
    resolved_today as (
      select count(*)::bigint as c
      from public.reports
      where status in ('resolved','dismissed')
        and resolved_at >= date_trunc('day', now())
    ),
    blocked_content_today as (
      select count(*)::bigint as c
      from public.moderation_actions
      where action in ('REMOVE_CONTENT','END_LIVE')
        and created_at >= date_trunc('day', now())
    ),
    blocked_users_today as (
      select count(*)::bigint as c
      from public.moderation_actions
      where action = 'BLOCK_USER'
        and created_at >= date_trunc('day', now())
    ),
    live_open_reports as (
      select count(*)::bigint as c
      from public.reports
      where status = 'open'
        and content_type = 'live'
    )
  select
    (select c from open_reports) as open_reports,
    (select c from resolved_today) as resolved_today,
    (select c from blocked_content_today) as blocked_content_today,
    (select c from blocked_users_today) as blocked_users_today,
    (select c from live_open_reports) as live_open_reports;
$$;
create or replace function public.moderation_reported_users_overview()
returns table (
  user_id text,
  role text,
  reports_count bigint,
  last_action text,
  last_action_at timestamptz,
  status text
)
language sql
stable
as $$
  with owners as (
    select
      content_owner_id as user_id,
      content_owner_type as role,
      count(*)::bigint as reports_count
    from public.reports
    where content_owner_id is not null
    group by content_owner_id, content_owner_type
  ),
  last_actions as (
    select distinct on (target_id)
      target_id as user_id,
      action as last_action,
      created_at as last_action_at
    from public.moderation_actions
    where target_type in ('user','artist','dj')
      and target_id is not null
    order by target_id, created_at desc
  )
  select
    o.user_id,
    coalesce(o.role, 'user') as role,
    o.reports_count,
    la.last_action,
    la.last_action_at,
    case
      when la.last_action = 'BLOCK_USER' then 'blocked'
      else 'active'
    end as status
  from owners o
  left join last_actions la using (user_id)
  order by o.reports_count desc, o.user_id;
$$;
