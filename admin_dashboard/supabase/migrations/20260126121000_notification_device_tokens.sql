-- Device token registry for push notifications (mobile app registration).
-- Stored via server-side API using service role; table is RLS-denied by default.

create table if not exists public.notification_device_tokens (
  token text primary key,
  user_uid text,
  platform text not null default 'unknown' check (platform in ('ios','android','web','unknown')),
  device_id text,
  country_code text,
  topics jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists notification_device_tokens_user_uid_idx
  on public.notification_device_tokens (user_uid);

create index if not exists notification_device_tokens_updated_at_idx
  on public.notification_device_tokens (updated_at desc);

alter table public.notification_device_tokens enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_device_tokens'
      and policyname = 'deny_all_notification_device_tokens'
  ) then
    create policy deny_all_notification_device_tokens
      on public.notification_device_tokens
      for all
      using (false)
      with check (false);
  end if;
end $$;
