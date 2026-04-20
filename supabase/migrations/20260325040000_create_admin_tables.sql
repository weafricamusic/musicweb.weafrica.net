-- Admin dashboard tables: audit logs, health checks, moderation reports, daily metrics.
--
-- These tables are backend-owned. Clients should access via Nest admin API.

create extension if not exists pgcrypto;

-- Admin audit logs
create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id text not null,
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table public.admin_audit_logs
  add column if not exists admin_id text,
  add column if not exists action text,
  add column if not exists target_type text,
  add column if not exists target_id text,
  add column if not exists details jsonb,
  add column if not exists ip_address text,
  add column if not exists user_agent text,
  add column if not exists created_at timestamptz;

update public.admin_audit_logs
set details = coalesce(details, '{}'::jsonb),
    created_at = coalesce(created_at, now())
where details is null or created_at is null;

-- System health checks
create table if not exists public.system_health (
  id uuid primary key default gen_random_uuid(),
  service text not null,
  status text not null check (status in ('healthy', 'degraded', 'down')),
  response_time_ms integer,
  error_message text,
  checked_at timestamptz not null default now()
);

alter table public.system_health
  add column if not exists service text,
  add column if not exists status text,
  add column if not exists response_time_ms integer,
  add column if not exists error_message text,
  add column if not exists checked_at timestamptz;

do $$
begin
  begin
    alter table public.system_health
      drop constraint if exists system_health_status_check;
  exception
    when undefined_object then null;
  end;

  alter table public.system_health
    add constraint system_health_status_check
    check (status in ('healthy', 'degraded', 'down'));
exception
  when duplicate_object then null;
end $$;

-- Content reports
create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id text not null,
  target_type text not null,
  target_id text not null,
  reason text not null,
  description text,
  status text not null default 'pending',
  details jsonb not null default '{}'::jsonb,
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.content_reports
  add column if not exists reporter_id text,
  add column if not exists target_type text,
  add column if not exists target_id text,
  add column if not exists reason text,
  add column if not exists description text,
  add column if not exists status text,
  add column if not exists details jsonb,
  add column if not exists reviewed_by text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists created_at timestamptz;

update public.content_reports
set details = coalesce(details, '{}'::jsonb),
    status = coalesce(nullif(trim(status), ''), 'pending'),
    created_at = coalesce(created_at, now())
where details is null or status is null or created_at is null;

-- Content flags (moderation queue)
create table if not exists public.content_flags (
  id uuid primary key default gen_random_uuid(),
  content_type text not null,
  content_id text not null,
  reported_by text not null,
  reason text not null,
  severity integer not null default 1,
  status text not null default 'pending',
  resolution text,
  resolution_notes text,
  resolved_by text,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.content_flags
  add column if not exists content_type text,
  add column if not exists content_id text,
  add column if not exists reported_by text,
  add column if not exists reason text,
  add column if not exists severity integer,
  add column if not exists status text,
  add column if not exists resolution text,
  add column if not exists resolution_notes text,
  add column if not exists resolved_by text,
  add column if not exists resolved_at timestamptz,
  add column if not exists created_at timestamptz;

update public.content_flags
set severity = coalesce(severity, 1),
    status = coalesce(nullif(trim(status), ''), 'pending'),
    created_at = coalesce(created_at, now())
where severity is null or status is null or created_at is null;

do $$
begin
  begin
    alter table public.content_flags
      drop constraint if exists content_flags_status_check;
  exception
    when undefined_object then null;
  end;

  alter table public.content_flags
    add constraint content_flags_status_check
    check (status in ('pending', 'resolved', 'dismissed'));
exception
  when duplicate_object then null;
end $$;

-- Viral alerts generated from feed monitoring.
create table if not exists public.viral_alerts (
  id uuid primary key default gen_random_uuid(),
  feed_item_id uuid references public.feed_items(id) on delete set null,
  item_type text,
  item_id text,
  title text,
  score numeric not null default 0,
  threshold numeric not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  acknowledged_by text,
  acknowledged_at timestamptz,
  triggered_at timestamptz not null default now()
);

alter table public.viral_alerts
  add column if not exists feed_item_id uuid,
  add column if not exists item_type text,
  add column if not exists item_id text,
  add column if not exists title text,
  add column if not exists score numeric,
  add column if not exists threshold numeric,
  add column if not exists metadata jsonb,
  add column if not exists acknowledged_by text,
  add column if not exists acknowledged_at timestamptz,
  add column if not exists triggered_at timestamptz;

update public.viral_alerts
set score = coalesce(score, 0),
    threshold = coalesce(threshold, 0),
    metadata = coalesce(metadata, '{}'::jsonb),
    triggered_at = coalesce(triggered_at, now())
where score is null or threshold is null or metadata is null or triggered_at is null;

-- Platform metrics (daily aggregates)
create table if not exists public.platform_metrics (
  id uuid primary key default gen_random_uuid(),
  date date not null unique,
  active_users integer not null default 0,
  new_users integer not null default 0,
  total_streams integer not null default 0,
  total_battles integer not null default 0,
  total_gifts bigint not null default 0,
  total_revenue numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.platform_metrics
  add column if not exists date date,
  add column if not exists active_users integer,
  add column if not exists new_users integer,
  add column if not exists total_streams integer,
  add column if not exists total_battles integer,
  add column if not exists total_gifts bigint,
  add column if not exists total_revenue numeric(14,2),
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

update public.platform_metrics
set
  active_users = coalesce(active_users, 0),
  new_users = coalesce(new_users, 0),
  total_streams = coalesce(total_streams, 0),
  total_battles = coalesce(total_battles, 0),
  total_gifts = coalesce(total_gifts, 0),
  total_revenue = coalesce(total_revenue, 0),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  active_users is null
  or new_users is null
  or total_streams is null
  or total_battles is null
  or total_gifts is null
  or total_revenue is null
  or created_at is null
  or updated_at is null;

-- Indexes
create index if not exists idx_admin_audit_admin on public.admin_audit_logs (admin_id);
create index if not exists idx_admin_audit_action on public.admin_audit_logs (action);
create index if not exists idx_admin_audit_created_at on public.admin_audit_logs (created_at desc);

create index if not exists idx_system_health_service_checked_at on public.system_health (service, checked_at desc);

create index if not exists idx_content_reports_status on public.content_reports (status);
create index if not exists idx_content_reports_target on public.content_reports (target_type, target_id);
create index if not exists idx_content_reports_created_at on public.content_reports (created_at desc);

create index if not exists idx_content_flags_status on public.content_flags (status);
create index if not exists idx_content_flags_target on public.content_flags (content_type, content_id);
create index if not exists idx_content_flags_created_at on public.content_flags (created_at desc);

create index if not exists idx_viral_alerts_triggered_at on public.viral_alerts (triggered_at desc);
create index if not exists idx_viral_alerts_acknowledged_by on public.viral_alerts (acknowledged_by);

create index if not exists idx_platform_metrics_date on public.platform_metrics (date);

-- RLS: deny all by default. Server uses service role.
alter table public.admin_audit_logs enable row level security;
alter table public.system_health enable row level security;
alter table public.content_reports enable row level security;
alter table public.content_flags enable row level security;
alter table public.platform_metrics enable row level security;
alter table public.viral_alerts enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'admin_audit_logs' and policyname = 'deny_all_admin_audit_logs'
  ) then
    create policy deny_all_admin_audit_logs on public.admin_audit_logs for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'system_health' and policyname = 'deny_all_system_health'
  ) then
    create policy deny_all_system_health on public.system_health for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'content_reports' and policyname = 'deny_all_content_reports'
  ) then
    create policy deny_all_content_reports on public.content_reports for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'content_flags' and policyname = 'deny_all_content_flags'
  ) then
    create policy deny_all_content_flags on public.content_flags for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'platform_metrics' and policyname = 'deny_all_platform_metrics'
  ) then
    create policy deny_all_platform_metrics on public.platform_metrics for all using (false) with check (false);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'viral_alerts' and policyname = 'deny_all_viral_alerts'
  ) then
    create policy deny_all_viral_alerts on public.viral_alerts for all using (false) with check (false);
  end if;
end $$;

revoke all on table public.admin_audit_logs from anon, authenticated;
revoke all on table public.system_health from anon, authenticated;
revoke all on table public.content_reports from anon, authenticated;
revoke all on table public.content_flags from anon, authenticated;
revoke all on table public.platform_metrics from anon, authenticated;
revoke all on table public.viral_alerts from anon, authenticated;

notify pgrst, 'reload schema';
