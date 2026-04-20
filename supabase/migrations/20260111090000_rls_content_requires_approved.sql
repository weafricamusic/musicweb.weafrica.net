-- STEP 10.5 — SUPABASE RLS: enforce approved + active for consumer reads
--
-- Aligns with WeAfrica core rule:
--   songs/videos are visible to consumer clients only when approved = true AND is_active = true
--
-- Notes:
-- - service_role (admin dashboard) bypasses RLS by design.
-- - authenticated owners (user_id = auth.uid()) can still manage their own rows.

-- Ensure columns exist (safe no-ops if already present)
alter table public.songs
  add column if not exists approved boolean not null default false;
alter table public.videos
  add column if not exists approved boolean not null default false;
-- Turn on hard enforcement
alter table public.songs enable row level security;
alter table public.songs force row level security;
alter table public.videos enable row level security;
alter table public.videos force row level security;
-- Drop ALL existing policies so visibility cannot be accidentally widened by older migrations.
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

  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'videos'
  loop
    execute format('drop policy if exists %I on public.videos', pol.policyname);
  end loop;
end $$;
-- Recreate policies (songs)
create policy "Public read approved active songs"
on public.songs
for select
to anon, authenticated
using (approved = true and is_active = true);
create policy "Artist manage own songs"
on public.songs
for all
to authenticated
using (auth.uid()::text = user_id::text)
with check (auth.uid()::text = user_id::text);
-- Recreate policies (videos)
create policy "Public read approved active videos"
on public.videos
for select
to anon, authenticated
using (approved = true and is_active = true);
create policy "Artist manage own videos"
on public.videos
for all
to authenticated
using (auth.uid()::text = user_id::text)
with check (auth.uid()::text = user_id::text);
