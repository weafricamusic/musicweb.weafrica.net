-- STEP 10.3 — SUPABASE RLS (HARD ENFORCEMENT): artists
--
-- Goals:
-- - Enable + force RLS
-- - Public (anon/authenticated) can READ only approved artists
-- - Artist can READ their own profile (auth.uid() = artists.user_id)
-- - Admin remains unrestricted via service_role (bypasses RLS)

alter table public.artists enable row level security;
alter table public.artists force row level security;
-- Hard enforcement: remove any existing/bypass policies on this table
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'artists'
  loop
    execute format('drop policy if exists %I on public.artists', pol.policyname);
  end loop;
end $$;
-- Public can read ONLY approved artists
create policy "Public read approved artists"
on public.artists
for select
to anon, authenticated
using (approved = true);
-- Artist can read their own profile
create policy "Artist read own profile"
on public.artists
for select
to authenticated
using (auth.uid()::text = user_id::text);
