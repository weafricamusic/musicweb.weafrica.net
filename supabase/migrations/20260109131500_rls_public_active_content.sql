-- STEP 8D: DB enforcement (consumer app)
-- Ensures consumer SELECTs only see is_active = true, even if a developer forgets the filter.
-- Note: service role (used by admin) bypasses RLS.

-- Enable RLS
alter table public.songs enable row level security;
alter table public.videos enable row level security;
-- Allow SELECT only for active content
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'songs'
      and policyname = 'public songs only'
  ) then
    create policy "public songs only"
    on public.songs
    for select
    using (is_active = true);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'videos'
      and policyname = 'public videos only'
  ) then
    create policy "public videos only"
    on public.videos
    for select
    using (is_active = true);
  end if;
end $$;
