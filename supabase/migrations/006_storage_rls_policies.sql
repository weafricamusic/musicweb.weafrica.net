-- Storage RLS policies to unblock uploads from the client.
--
-- IMPORTANT SECURITY NOTE:
-- These policies allow PUBLIC (anon) reads + uploads to specific buckets.
-- This is okay for MVP/testing, but not recommended for production.
-- For production, prefer:
--   - Supabase Auth (authenticated user), or
--   - an Edge Function / server using the service role to create signed upload URLs.


do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read profile_images'
  ) then
    execute $pol$
      create policy "public read profile_images"
        on storage.objects for select
        using (bucket_id = 'profile_images');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read cover_images'
  ) then
    execute $pol$
      create policy "public read cover_images"
        on storage.objects for select
        using (bucket_id = 'cover_images');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read songs'
  ) then
    execute $pol$
      create policy "public read songs"
        on storage.objects for select
        using (bucket_id = 'songs');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read song_thumbnails'
  ) then
    execute $pol$
      create policy "public read song_thumbnails"
        on storage.objects for select
        using (bucket_id = 'song_thumbnails');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read videos'
  ) then
    execute $pol$
      create policy "public read videos"
        on storage.objects for select
        using (bucket_id = 'videos');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public read video_thumbnails'
  ) then
    execute $pol$
      create policy "public read video_thumbnails"
        on storage.objects for select
        using (bucket_id = 'video_thumbnails');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload profile_images'
  ) then
    execute $pol$
      create policy "public upload profile_images"
        on storage.objects for insert
        with check (bucket_id = 'profile_images');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload cover_images'
  ) then
    execute $pol$
      create policy "public upload cover_images"
        on storage.objects for insert
        with check (bucket_id = 'cover_images');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload songs'
  ) then
    execute $pol$
      create policy "public upload songs"
        on storage.objects for insert
        with check (bucket_id = 'songs');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload song_thumbnails'
  ) then
    execute $pol$
      create policy "public upload song_thumbnails"
        on storage.objects for insert
        with check (bucket_id = 'song_thumbnails');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload videos'
  ) then
    execute $pol$
      create policy "public upload videos"
        on storage.objects for insert
        with check (bucket_id = 'videos');
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'public upload video_thumbnails'
  ) then
    execute $pol$
      create policy "public upload video_thumbnails"
        on storage.objects for insert
        with check (bucket_id = 'video_thumbnails');
    $pol$;
  end if;
end $$;
