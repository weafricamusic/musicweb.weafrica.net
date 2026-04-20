-- Push Notification System Schema
-- Comprehensive notification infrastructure for WEAFRICA MUSIC

-- ============================================================================
-- 1. NOTIFICATION DEVICE TOKENS TABLE
-- ============================================================================
create table if not exists public.notification_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null,
  platform text not null check (platform in ('ios', 'android', 'web')),
  is_active boolean not null default true,
  country_code text, -- ISO 3166-1 alpha-2
  app_version text,
  device_model text,
  last_updated timestamp with time zone not null default now(),
  created_at timestamp with time zone not null default now(),
  
  -- Ensure uniqueness per user/device
  constraint unique_fcm_token unique (fcm_token)
);

create index idx_notification_device_tokens_user_id on public.notification_device_tokens(user_id);
create index idx_notification_device_tokens_is_active on public.notification_device_tokens(is_active);
create index idx_notification_device_tokens_platform on public.notification_device_tokens(platform);
create index idx_notification_device_tokens_country on public.notification_device_tokens(country_code);
create index idx_notification_device_tokens_last_updated on public.notification_device_tokens(last_updated desc);

-- ============================================================================
-- 2. NOTIFICATIONS TABLE
-- ============================================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete set null, -- Admin user
  title text not null,
  body text not null,
  notification_type text not null check (
    notification_type in (
      'like_update', 'comment_update', 'live_battle', 
      'coin_reward', 'new_song', 'new_video',
      'follow_notification', 'collaboration_invite',
      'system_announcement'
    )
  ),
  payload jsonb not null, -- Data to send with FCM message
  
  -- Targeting/filtering
  target_roles text[] default array['consumer', 'artist', 'dj'], -- Roles to target
  target_countries text[] default null, -- If null, send to all; else restrict to list
  scheduled_at timestamp with time zone not null default now(),
  
  -- Metadata
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'sent', 'failed')),
  total_recipients integer default 0,
  total_sent integer default 0,
  total_delivered integer default 0,
  total_opened integer default 0,
  failure_reason text,
  
  created_at timestamp with time zone not null default now(),
  sent_at timestamp with time zone,
  updated_at timestamp with time zone not null default now()
);

create index idx_notifications_status on public.notifications(status);
create index idx_notifications_type on public.notifications(notification_type);
create index idx_notifications_scheduled_at on public.notifications(scheduled_at);
create index idx_notifications_created_by on public.notifications(created_by);
create index idx_notifications_created_at on public.notifications(created_at desc);

-- ============================================================================
-- 3. NOTIFICATION RECIPIENTS TRACKING
-- ============================================================================
create table if not exists public.notification_recipients (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token_id uuid not null references public.notification_device_tokens(id) on delete cascade,
  
  status text not null default 'pending' check (status in ('pending', 'sent', 'delivered', 'failed', 'opened')),
  failure_reason text,
  
  sent_at timestamp with time zone,
  delivered_at timestamp with time zone,
  opened_at timestamp with time zone,
  
  created_at timestamp with time zone not null default now()
);

create index idx_notification_recipients_notification_id on public.notification_recipients(notification_id);
create index idx_notification_recipients_user_id on public.notification_recipients(user_id);
create index idx_notification_recipients_status on public.notification_recipients(status);
create index idx_notification_recipients_device_token_id on public.notification_recipients(device_token_id);

-- ============================================================================
-- 4. NOTIFICATION ENGAGEMENT LOGS
-- ============================================================================
create table if not exists public.notification_engagement (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  event_type text not null check (event_type in ('delivered', 'opened', 'clicked', 'dismissed')),
  action_metadata jsonb, -- Additional data (e.g., clicked screen, entity_id)
  
  created_at timestamp with time zone not null default now()
);

create index idx_notification_engagement_notification_id on public.notification_engagement(notification_id);
create index idx_notification_engagement_user_id on public.notification_engagement(user_id);
create index idx_notification_engagement_event_type on public.notification_engagement(event_type);
create index idx_notification_engagement_created_at on public.notification_engagement(created_at desc);

-- ============================================================================
-- 5. ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Device tokens: Users can view/manage their own tokens
alter table public.notification_device_tokens enable row level security;

create policy "Users can view own device tokens"
  on public.notification_device_tokens for select
  using (auth.uid() = user_id);

create policy "Users can insert own device tokens"
  on public.notification_device_tokens for insert
  with check (auth.uid() = user_id);

create policy "Users can update own device tokens"
  on public.notification_device_tokens for update
  using (auth.uid() = user_id);

create policy "Users can delete own device tokens"
  on public.notification_device_tokens for delete
  using (auth.uid() = user_id);

-- Notifications: Only admins can create/update; all can view
alter table public.notifications enable row level security;

create policy "Admins can manage notifications"
  on public.notifications for all
  using (
    exists (
      select 1 from public.users
      where users.id = auth.uid()
      and users.role = 'admin'
    )
  );

create policy "All users can view notifications"
  on public.notifications for select
  using (true);

-- Notification recipients: Users can view their own recipient records
alter table public.notification_recipients enable row level security;

create policy "Users can view own notification recipients"
  on public.notification_recipients for select
  using (auth.uid() = user_id);

-- Engagement logs: Users can view their own, admins can view all
alter table public.notification_engagement enable row level security;

create policy "Users can view own engagement logs"
  on public.notification_engagement for select
  using (auth.uid() = user_id);

create policy "Admins can view all engagement logs"
  on public.notification_engagement for select
  using (
    exists (
      select 1 from public.users
      where users.id = auth.uid()
      and users.role = 'admin'
    )
  );

create policy "Backend service can insert engagement logs"
  on public.notification_engagement for insert
  with check (true); -- Backend authenticated via service role

-- ============================================================================
-- 6. ANALYTICS VIEWS
-- ============================================================================

-- Overall notification performance
create or replace view public.notification_performance_summary as
select
  count(distinct n.id) as total_notifications,
  count(distinct n.id) filter (where n.status = 'sent') as sent,
  count(distinct nr.id) filter (where nr.status = 'delivered') as total_delivered,
  count(distinct nr.id) filter (where nr.status = 'opened') as total_opened,
  round(
    100.0 * count(distinct nr.id) filter (where nr.status in ('delivered', 'opened')) /
    nullif(count(distinct nr.id) filter (where nr.status != 'pending'), 0),
    2
  ) as delivery_rate_pct,
  round(
    100.0 * count(distinct nr.id) filter (where nr.status = 'opened') /
    nullif(count(distinct nr.id) filter (where nr.status in ('delivered', 'opened')), 0),
    2
  ) as open_rate_pct
from public.notifications n
left join public.notification_recipients nr on n.id = nr.notification_id
where n.created_at >= now() - interval '30 days';

-- Performance by notification type
create or replace view public.notification_performance_by_type as
select
  n.notification_type,
  count(distinct n.id) as total,
  count(distinct nr.id) filter (where nr.status = 'sent') as sent,
  count(distinct nr.id) filter (where nr.status = 'delivered') as delivered,
  count(distinct nr.id) filter (where nr.status = 'opened') as opened,
  round(
    100.0 * count(distinct nr.id) filter (where nr.status in ('delivered', 'opened')) /
    nullif(count(distinct nr.id) filter (where nr.status != 'pending'), 0),
    2
  ) as delivery_rate_pct
from public.notifications n
left join public.notification_recipients nr on n.id = nr.notification_id
where n.created_at >= now() - interval '30 days'
group by n.notification_type
order by total desc;

-- Device token health
create or replace view public.notification_token_health as
select
  platform,
  count(*) as total_tokens,
  count(*) filter (where is_active = true) as active_tokens,
  round(
    100.0 * count(*) filter (where is_active = true) / count(*),
    2
  ) as active_percentage,
  max(last_updated) as last_sync_time
from public.notification_device_tokens
group by platform;
