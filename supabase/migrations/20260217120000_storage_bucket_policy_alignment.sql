-- Align Storage bucket policies with actual Flutter upload bucket names.
--
-- App buckets in current code:
-- - avatars (profile edit)
-- - songs, song-thumbnails (track upload)
-- - media, thumbnails (video upload)

-- Ensure buckets exist (public read URLs are used by the app).
do $$
begin
  insert into storage.buckets (id, name, public)
  values
    ('avatars', 'avatars', true),
    ('songs', 'songs', true),
    ('song-thumbnails', 'song-thumbnails', true),
    ('media', 'media', true),
    ('thumbnails', 'thumbnails', true)
  on conflict (id) do update
  set public = excluded.public;
exception
  when insufficient_privilege then
    -- Some hosted setups restrict direct writes to storage tables.
    null;
end $$;

do $$
begin
  execute 'alter table storage.objects enable row level security';
exception
  when insufficient_privilege then
    -- Only the storage schema owner can toggle RLS.
    null;
end $$;

-- Read policies
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read avatars'
  ) then
    execute 'create policy "public read avatars" on storage.objects for select using (bucket_id = ''avatars'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read songs (aligned)'
  ) then
    execute 'create policy "public read songs (aligned)" on storage.objects for select using (bucket_id = ''songs'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read song-thumbnails'
  ) then
    execute 'create policy "public read song-thumbnails" on storage.objects for select using (bucket_id = ''song-thumbnails'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read media'
  ) then
    execute 'create policy "public read media" on storage.objects for select using (bucket_id = ''media'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read thumbnails'
  ) then
    execute 'create policy "public read thumbnails" on storage.objects for select using (bucket_id = ''thumbnails'')';
  end if;
exception
  when insufficient_privilege then
    null;
end
$$;

-- Insert/upload policies (anon/authenticated client uploads)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload avatars'
  ) then
    execute 'create policy "public upload avatars" on storage.objects for insert with check (bucket_id = ''avatars'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload songs (aligned)'
  ) then
    execute 'create policy "public upload songs (aligned)" on storage.objects for insert with check (bucket_id = ''songs'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload song-thumbnails'
  ) then
    execute 'create policy "public upload song-thumbnails" on storage.objects for insert with check (bucket_id = ''song-thumbnails'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload media'
  ) then
    execute 'create policy "public upload media" on storage.objects for insert with check (bucket_id = ''media'')';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload thumbnails'
  ) then
    execute 'create policy "public upload thumbnails" on storage.objects for insert with check (bucket_id = ''thumbnails'')';
  end if;
exception
  when insufficient_privilege then
    null;
end
$$;

-- Update policy needed for avatar upsert=true overwrite behavior.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public update avatars'
  ) then
    execute 'create policy "public update avatars" on storage.objects for update using (bucket_id = ''avatars'') with check (bucket_id = ''avatars'')';
  end if;
exception
  when insufficient_privilege then
    null;
end
$$;
