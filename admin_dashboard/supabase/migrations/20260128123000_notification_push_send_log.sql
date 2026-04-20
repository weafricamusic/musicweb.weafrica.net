-- Push send log for frequency/rate limiting (e.g. trending 1–2/day)
-- Stored via server-side API using service role; table is RLS-denied by default.

create table if not exists public.notification_push_send_log (
  id bigserial primary key,
  user_uid text not null,
  token_topic text not null,
  day date not null,
  created_at timestamptz not null default now()
);

create index if not exists notification_push_send_log_user_topic_day_idx
  on public.notification_push_send_log (user_uid, token_topic, day);

create index if not exists notification_push_send_log_created_at_idx
  on public.notification_push_send_log (created_at desc);

alter table public.notification_push_send_log enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_push_send_log'
      and policyname = 'deny_all_notification_push_send_log'
  ) then
    create policy deny_all_notification_push_send_log
      on public.notification_push_send_log
      for all
      using (false)
      with check (false);
  end if;
end $$;
