-- LIVE CHAT (SESSION-LINKED)
--
-- Consumer live chat backed by Supabase Realtime, linked to a specific live session.
-- Note: app identity uses Firebase UID (text), not Supabase auth.users.

create table if not exists public.live_messages (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.live_sessions(id) on delete cascade,
  user_id text not null,
  username text not null,
  kind text not null default 'message',
  message text not null,
  created_at timestamptz not null default now()
);

do $$
begin
  alter table public.live_messages
    add constraint live_messages_kind_check
    check (kind in ('message', 'system', 'gift'));
exception
  when duplicate_object then null;
end $$;

create index if not exists live_messages_live_created_at_idx
  on public.live_messages (live_id, created_at desc);

alter table public.live_messages enable row level security;

do $$
begin
  create policy "Public read live messages" on public.live_messages
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create policy "Public write live messages" on public.live_messages
    for insert
    to anon, authenticated
    with check (true);
exception
  when duplicate_object then null;
end $$;

grant select, insert on table public.live_messages to anon, authenticated;

-- Realtime
-- (If the table is already added, ignore.)
do $$
begin
  alter publication supabase_realtime add table public.live_messages;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
