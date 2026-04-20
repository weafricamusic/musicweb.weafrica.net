-- Per-user Notification Center table.
--
-- This repo uses Firebase Auth; reads/writes should happen via Edge API using the
-- service role (not via client RLS).

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_uid text not null,
  type text not null default 'general',
  title text,
  body text,
  data jsonb not null default '{}'::jsonb,
  read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table if exists public.notifications
  add column if not exists user_uid text;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notifications'
      and column_name = 'user_id'
  ) then
    execute 'update public.notifications set user_uid = user_id::text where user_uid is null';
  end if;
end $$;

create index if not exists notifications_user_uid_created_at_idx
  on public.notifications (user_uid, created_at desc);

create index if not exists notifications_user_uid_read_idx
  on public.notifications (user_uid, read);

alter table public.notifications enable row level security;

do $$
begin
  -- Default to deny-all from client roles; Edge API uses service role.
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname = 'deny_all_notifications'
  ) then
    create policy deny_all_notifications
      on public.notifications
      for all
      using (false)
      with check (false);
  end if;
end $$;
