-- Supabase schema for notifications and FCM tokens

-- 1) Add fcm_token and coins to users table
alter table public.users
  add column if not exists fcm_token text,
  add column if not exists fcm_updated_at timestamptz,
  add column if not exists coins integer default 0,
  add column if not exists last_bonus_date timestamptz;

-- 2) Create notifications table
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade not null,
  
  -- Notification content
  title text not null,
  body text,
  
  -- Type determines handling (like, comment, coin, etc)
  type text not null default 'general',
  
  -- Optional data payload (JSON)
  data jsonb default '{}'::jsonb,
  
  -- Entity reference (track_id, battle_id, etc)
  entity_id text,
  entity_type text,
  
  -- Status
  read boolean default false,
  clicked boolean default false,
  
  -- Timestamps
  created_at timestamptz default now(),
  read_at timestamptz,
  clicked_at timestamptz
);

-- 3) Index for fast queries
create index if not exists idx_notifications_user_created
  on public.notifications(user_id, created_at desc);

create index if not exists idx_notifications_unread
  on public.notifications(user_id, read) where read = false;

-- 4) RLS policies
alter table public.notifications enable row level security;

-- Users can read their own notifications
create policy "Users can read own notifications"
  on public.notifications
  for select
  using (auth.uid() = user_id);

-- Users can update their own notifications (mark as read)
create policy "Users can update own notifications"
  on public.notifications
  for update
  using (auth.uid() = user_id);

-- Service role can insert notifications
create policy "Service can insert notifications"
  on public.notifications
  for insert
  with check (true);

-- 5) Function to get unread count
create or replace function public.get_unread_count(user_uuid uuid)
returns integer
language sql
security definer
as $$
  select count(*)::integer
  from public.notifications
  where user_id = user_uuid and read = false;
$$;

-- 6) Function to send notification via FCM (placeholder - implement in backend)
create or replace function public.send_push_notification(
  p_user_id uuid,
  p_title text,
  p_body text default null,
  p_type text default 'general',
  p_data jsonb default '{}'::jsonb,
  p_silent boolean default false
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_notification_id uuid;
  v_fcm_token text;
begin
  -- Create notification record
  insert into public.notifications (user_id, title, body, type, data)
  values (p_user_id, p_title, p_body, p_type, p_data)
  returning id into v_notification_id;

  -- Get user's FCM token
  select fcm_token into v_fcm_token
  from public.users
  where id = p_user_id;

  -- TODO: Call Firebase Cloud Messaging API via HTTP
  -- For now, just return the notification ID
  -- In production, use a Edge Function or background job to send FCM

  return v_notification_id;
end;
$$;

-- 7) Example: Daily bonus trigger
create or replace function public.claim_daily_bonus(user_uuid uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_last_bonus timestamptz;
  v_today timestamptz;
  v_bonus_amount integer := 50;
  v_new_balance integer;
begin
  -- Get last bonus date
  select last_bonus_date into v_last_bonus
  from public.users
  where id = user_uuid;

  v_today := current_date;

  -- Check if already claimed today
  if v_last_bonus is not null and date(v_last_bonus) = date(v_today) then
    return jsonb_build_object(
      'success', false,
      'error', 'Already claimed today'
    );
  end if;

  -- Update coins and last_bonus_date
  update public.users
  set 
    coins = coalesce(coins, 0) + v_bonus_amount,
    last_bonus_date = now()
  where id = user_uuid
  returning coins into v_new_balance;

  -- Send silent notification
  perform public.send_push_notification(
    user_uuid,
    'Daily Bonus',
    format('You received %s coins!', v_bonus_amount),
    'daily_bonus',
    jsonb_build_object('amount', v_bonus_amount, 'balance', v_new_balance),
    true
  );

  return jsonb_build_object(
    'success', true,
    'amount', v_bonus_amount,
    'balance', v_new_balance
  );
end;
$$;

-- 8) Grant permissions
grant usage on schema public to anon, authenticated;
grant select on public.notifications to authenticated;
grant update on public.notifications to authenticated;
grant execute on function public.get_unread_count(uuid) to authenticated;
grant execute on function public.claim_daily_bonus(uuid) to authenticated;

comment on table public.notifications is 'User notifications with FCM support';
comment on function public.send_push_notification is 'Send push notification to user (implement FCM call in Edge Function)';
comment on function public.claim_daily_bonus is 'Claim daily coin bonus (once per day)';
