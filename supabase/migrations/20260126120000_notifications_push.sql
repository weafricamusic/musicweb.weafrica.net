-- Push notifications admin scaffolding.

create table if not exists public.notification_push_messages (
  id uuid primary key default gen_random_uuid(),
  title text,
  body text not null,
  topic text not null default 'all',
  data jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','sent','failed','archived')),
  sent_at timestamptz,
  error text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notification_push_messages_created_at_idx
  on public.notification_push_messages (created_at desc);
alter table public.notification_push_messages enable row level security;
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_push_messages'
      and policyname = 'deny_all_notification_push_messages'
  ) then
    create policy deny_all_notification_push_messages
      on public.notification_push_messages
      for all
      using (false)
      with check (false);
  end if;
end $$;
