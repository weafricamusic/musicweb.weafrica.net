-- Announcements (simple in-app notifications)
-- Stored in public.announcements and readable by the consumer app.

create extension if not exists pgcrypto;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  -- Canonical format: 'all' OR comma-separated segments like 'artists,djs'.
  target text not null default 'all',
  action_link text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint announcements_target_format check (
    target = 'all' or target ~ '^(artists|djs|consumers)(,(artists|djs|consumers))*$'
  )
);

create index if not exists announcements_is_active_idx on public.announcements (is_active);
create index if not exists announcements_created_at_idx on public.announcements (created_at desc);

alter table public.announcements enable row level security;

-- Default deny-all; admin writes use service role.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'announcements'
      and policyname = 'deny_all_announcements'
  ) then
    create policy deny_all_announcements
      on public.announcements
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Public read of active announcements.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'announcements'
      and policyname = 'public_read_active_announcements'
  ) then
    create policy public_read_active_announcements
      on public.announcements
      for select
      using (is_active = true);
  end if;
end $$;

grant select on table public.announcements to anon, authenticated;

-- Admin writes use the service-role key (bypasses RLS).
grant usage on schema public to anon, authenticated;
grant all on table public.announcements to service_role;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
