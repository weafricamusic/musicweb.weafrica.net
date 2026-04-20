-- STEP 10.1 — SUPABASE RLS (HARD ENFORCEMENT): songs
--
-- Goals:
-- - Enable + force RLS
-- - Public (anon/authenticated) can READ only active songs
-- - Artists can manage ONLY their own songs (by auth.uid() = songs.user_id)
-- - Admin remains unrestricted via service_role (bypasses RLS)

alter table public.songs enable row level security;
alter table public.songs force row level security;
-- Hard enforcement: remove any existing/bypass policies on this table
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'songs'
  loop
    execute format('drop policy if exists %I on public.songs', pol.policyname);
  end loop;
end $$;
-- Public can read ONLY active songs
create policy "Public read active songs"
on public.songs
for select
to anon, authenticated
using (is_active = true);
-- Artist can manage ONLY their own songs
create policy "Artist manage own songs"
on public.songs
for all
to authenticated
using (auth.uid()::text = user_id::text)
with check (auth.uid()::text = user_id::text);
