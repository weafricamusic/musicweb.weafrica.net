-- STEP 10.2 — SUPABASE RLS (HARD ENFORCEMENT): videos
--
-- Goals:
-- - Enable + force RLS
-- - Public (anon/authenticated) can READ only active videos
-- - Artists can manage ONLY their own videos (by auth.uid() = videos.user_id)
-- - Admin remains unrestricted via service_role (bypasses RLS)

alter table public.videos enable row level security;
alter table public.videos force row level security;

-- Hard enforcement: remove any existing/bypass policies on this table
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'videos'
  loop
    execute format('drop policy if exists %I on public.videos', pol.policyname);
  end loop;
end $$;

-- Public can read ONLY active videos
create policy "Public read active videos"
on public.videos
for select
to anon, authenticated
using (is_active = true);

-- Artist can manage ONLY their own videos
create policy "Artist manage own videos"
on public.videos
for all
to authenticated
using (auth.uid()::text = user_id::text)
with check (auth.uid()::text = user_id::text);
