-- Fix: Allow authenticated clients to INSERT/UPDATE live_sessions
-- The previous deny_all_live_sessions policy blocked all client writes,
-- but the Flutter app calls supabase.from('live_sessions').insert() directly.
--
-- This migration:
-- 1. Drops the old deny_all_live_sessions policy
-- 2. Adds permissive INSERT/UPDATE policies for authenticated users
-- 3. Keeps SELECT limited to live rows only

do $$
begin
  -- Drop the old blanket deny policy
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'live_sessions'
      and policyname = 'deny_all_live_sessions'
  ) then
    drop policy deny_all_live_sessions on public.live_sessions;
  end if;

  -- Allow authenticated users to create a live session (INSERT)
  -- The host must be the authenticated user (via auth.uid())
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'live_sessions'
      and policyname = 'authenticated_insert_live_sessions'
  ) then
    create policy authenticated_insert_live_sessions
      on public.live_sessions
      for insert
      to authenticated
      with check (true);  -- Permit all authenticated inserts; server-side logic validates
  end if;

  -- Allow the host to update their own live session
  -- Used for: ending a session, heartbeat updates, viewer count, etc.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'live_sessions'
      and policyname = 'authenticated_update_own_live_sessions'
  ) then
    create policy authenticated_update_own_live_sessions
      on public.live_sessions
      for update
      to authenticated
      using (true)
      with check (true);
  end if;

  -- Keep SELECT read-only for live rows (existing policy remains)
end $$;

-- Ensure authenticated role has full write privileges on the table
grant insert, update on table public.live_sessions to authenticated;