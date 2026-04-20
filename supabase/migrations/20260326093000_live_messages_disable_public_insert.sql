-- Tighten live_messages writes for production.
--
-- Clients should NOT insert into live_messages directly at 10k scale.
-- Edge (service_role) is the authoritative writer for:
-- - chat messages (rate-limited)
-- - gift fanout events
-- - system messages

alter table public.live_messages enable row level security;

-- Remove permissive insert policy if it exists.
drop policy if exists "Public write live messages" on public.live_messages;

-- Keep public read for streaming.
do $$
begin
  create policy "Public read live messages" on public.live_messages
    for select
    to anon, authenticated
    using (true);
exception
  when duplicate_object then null;
end $$;

-- Revoke direct inserts from client roles.
revoke insert on table public.live_messages from anon, authenticated;

-- Service role can still insert (bypasses RLS; grant kept explicit).
grant insert on table public.live_messages to service_role;
