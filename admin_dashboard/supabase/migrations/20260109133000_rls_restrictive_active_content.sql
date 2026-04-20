-- STEP 8D (hardening): Make active-content enforcement non-bypassable
--
-- Why: Your DB already has permissive SELECT policies like "Allow all songs" / "public select songs".
-- Permissive policies are OR'ed, so a single broad policy can allow inactive rows.
--
-- Fix: Add RESTRICTIVE SELECT policies that require is_active=true.
-- Restrictive policies are AND'ed with the permissive result, so they cannot be bypassed
-- (except by the service role, which bypasses RLS by design).

alter table public.songs enable row level security;
alter table public.videos enable row level security;

-- Songs: require is_active = true for all SELECTs (non-service roles)
drop policy if exists "active songs only (restrictive)" on public.songs;
create policy "active songs only (restrictive)"
on public.songs
as restrictive
for select
using (is_active = true);

-- Videos: require is_active = true for all SELECTs (non-service roles)
drop policy if exists "active videos only (restrictive)" on public.videos;
create policy "active videos only (restrictive)"
on public.videos
as restrictive
for select
using (is_active = true);
