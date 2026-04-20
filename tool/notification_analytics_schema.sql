-- Notification Analytics Schema
-- Tracks delivery, opens, and engagement metrics for push notifications

-- 1) Main notification logs table
create table if not exists public.notification_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null, -- FCM device token
  type text not null, -- 'like_update', 'comment_update', 'live_battle', 'coin_reward', 'new_song', etc.
  payload jsonb not null, -- Original FCM payload
  status text not null default 'sent', -- 'sent', 'delivered', 'failed', 'opened', 'clicked'
  country_code text, -- User's country (ISO 3166-1 alpha-2)
  role text, -- 'consumer', 'artist', 'dj'
  created_at timestamp with time zone not null default now(),
  delivered_at timestamp with time zone, -- When device acknowledged receipt
  opened_at timestamp with time zone, -- When user tapped notification
  clicked_at timestamp with time zone, -- When user completed action (optional)
  failure_reason text, -- Error message if status = 'failed'
  
  constraint valid_status check (status in ('sent', 'delivered', 'failed', 'opened', 'clicked')),
  constraint valid_role check (role in ('consumer', 'artist', 'dj'))
);

-- Indexes for fast queries
create index idx_notification_logs_user_id on public.notification_logs(user_id);
create index idx_notification_logs_status on public.notification_logs(status);
create index idx_notification_logs_type on public.notification_logs(type);
create index idx_notification_logs_country on public.notification_logs(country_code);
create index idx_notification_logs_role on public.notification_logs(role);
create index idx_notification_logs_created_at on public.notification_logs(created_at desc);

-- 2) Analytics views for common queries

-- Overall delivery stats
create or replace view public.notification_delivery_stats as
select
  count(*) filter (where status in ('sent', 'delivered', 'opened', 'clicked')) as total_sent,
  count(*) filter (where status in ('delivered', 'opened', 'clicked')) as total_delivered,
  count(*) filter (where status in ('opened', 'clicked')) as total_opened,
  count(*) filter (where status = 'failed') as total_failed,
  round(
    100.0 * count(*) filter (where status in ('delivered', 'opened', 'clicked')) /
    nullif(count(*) filter (where status in ('sent', 'delivered', 'opened', 'clicked')), 0),
    2
  ) as delivery_rate_pct,
  round(
    100.0 * count(*) filter (where status in ('opened', 'clicked')) /
    nullif(count(*) filter (where status in ('delivered', 'opened', 'clicked')), 0),
    2
  ) as open_rate_pct
from public.notification_logs
where created_at >= now() - interval '30 days';

-- Performance by notification type
create or replace view public.notification_stats_by_type as
select
  type,
  count(*) as sent,
  count(*) filter (where status in ('delivered', 'opened', 'clicked')) as delivered,
  count(*) filter (where status in ('opened', 'clicked')) as opened,
  round(
    100.0 * count(*) filter (where status in ('delivered', 'opened', 'clicked')) /
    nullif(count(*), 0),
    2
  ) as delivery_rate_pct,
  round(
    100.0 * count(*) filter (where status in ('opened', 'clicked')) /
    nullif(count(*) filter (where status in ('delivered', 'opened', 'clicked')), 0),
    2
  ) as open_rate_pct,
  round(avg(extract(epoch from (opened_at - created_at)))) as avg_time_to_open_sec
from public.notification_logs
where created_at >= now() - interval '30 days'
group by type
order by sent desc;

-- Performance by country
create or replace view public.notification_stats_by_country as
select
  country_code,
  count(*) as sent,
  count(*) filter (where status in ('delivered', 'opened', 'clicked')) as delivered,
  count(*) filter (where status in ('opened', 'clicked')) as opened,
  round(
    100.0 * count(*) filter (where status in ('delivered', 'opened', 'clicked')) /
    nullify(count(*), 0),
    2
  ) as delivery_rate_pct,
  round(
    100.0 * count(*) filter (where status in ('opened', 'clicked')) /
    nullif(count(*) filter (where status in ('delivered', 'opened', 'clicked')), 0),
    2
  ) as open_rate_pct
from public.notification_logs
where created_at >= now() - interval '30 days' and country_code is not null
group by country_code
order by sent desc;

-- Performance by role
create or replace view public.notification_stats_by_role as
select
  role,
  count(*) as sent,
  count(*) filter (where status in ('delivered', 'opened', 'clicked')) as delivered,
  count(*) filter (where status in ('opened', 'clicked')) as opened,
  round(
    100.0 * count(*) filter (where status in ('delivered', 'opened', 'clicked')) /
    nullif(count(*), 0),
    2
  ) as delivery_rate_pct,
  round(
    100.0 * count(*) filter (where status in ('opened', 'clicked')) /
    nullif(count(*) filter (where status in ('delivered', 'opened', 'clicked')), 0),
    2
  ) as open_rate_pct
from public.notification_logs
where created_at >= now() - interval '30 days' and role is not null
group by role
order by sent desc;

-- Hourly delivery trend (last 7 days)
create or replace view public.notification_hourly_trends as
select
  date_trunc('hour', created_at) as hour,
  count(*) as sent,
  count(*) filter (where status in ('delivered', 'opened', 'clicked')) as delivered,
  count(*) filter (where status in ('opened', 'clicked')) as opened,
  round(
    100.0 * count(*) filter (where status in ('delivered', 'opened', 'clicked')) /
    nullif(count(*), 0),
    2
  ) as delivery_rate_pct
from public.notification_logs
where created_at >= now() - interval '7 days'
group by date_trunc('hour', created_at)
order by hour desc;

-- Device token health (invalid tokens)
create or replace view public.notification_token_health as
select
  token,
  count(*) as total_attempts,
  count(*) filter (where status = 'failed') as failed_attempts,
  round(
    100.0 * count(*) filter (where status = 'failed') / count(*),
    2
  ) as failure_rate_pct,
  max(created_at) as last_attempt,
  string_agg(distinct failure_reason, ', ') as failure_reasons
from public.notification_logs
where created_at >= now() - interval '7 days'
group by token
having count(*) filter (where status = 'failed') > 0
order by failure_rate_pct desc;

-- Row-level security
alter table public.notification_logs enable row level security;

-- Admin users can view all notification logs
create policy "admin_notification_logs_access" on public.notification_logs
  for all
  using (auth.jwt() ->> 'role' = 'admin')
  with check (auth.jwt() ->> 'role' = 'admin');

-- Users can view their own notification logs
create policy "users_own_notification_logs" on public.notification_logs
  for select
  using (user_id = auth.uid());
