-- STEP 1 (BASE LIVE SCREEN) schema
-- Minimal schema: chat + likes only.

-- LIVE CHAT MESSAGES
create table if not exists public.live_chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id text not null,
  user_id text not null,
  username text not null,
  message text not null,
  created_at timestamptz not null default now()
);
create index if not exists live_chat_messages_channel_created_at_idx
  on public.live_chat_messages (channel_id, created_at desc);
alter table public.live_chat_messages enable row level security;
do $$
begin
  create policy "Public read live chat" on public.live_chat_messages
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;
do $$
begin
  create policy "Public write live chat" on public.live_chat_messages
    for insert
    to anon, authenticated
    with check (true);
exception
  when duplicate_object then null;
end $$;
-- LIVE LIKE COUNTER
create table if not exists public.live_like_counters (
  channel_id text primary key,
  count bigint not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.live_like_counters enable row level security;
do $$
begin
  create policy "Public read live likes" on public.live_like_counters
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;
do $$
begin
  create policy "Public write live likes" on public.live_like_counters
    for insert
    to anon, authenticated
    with check (true);
exception
  when duplicate_object then null;
end $$;
do $$
begin
  create policy "Public update live likes" on public.live_like_counters
    for update
    to anon, authenticated
    using (true)
    with check (true);
exception
  when duplicate_object then null;
end $$;
-- Atomic increment for likes
create or replace function public.increment_live_likes(p_channel_id text)
returns bigint
language plpgsql
as $$
declare
  new_count bigint;
begin
  insert into public.live_like_counters(channel_id, count)
  values (p_channel_id, 1)
  on conflict (channel_id) do update
    set count = public.live_like_counters.count + 1,
        updated_at = now()
  returning count into new_count;

  return new_count;
end;
$$;
-- Grants (needed when RLS is enabled)
grant select, insert on table public.live_chat_messages to anon, authenticated;
grant select, insert, update on table public.live_like_counters to anon, authenticated;
grant execute on function public.increment_live_likes(text) to anon, authenticated;
