-- Ensure the DJ sets storage bucket exists.
-- The mobile app uploads DJ mixes/sets using bucket id: "dj-sets".
--
-- If this bucket is missing, uploads will fail with: "Bucket not found".
--
-- Note: Marking it public keeps the app's stored URLs stable (it uses getPublicUrl).

insert into storage.buckets (id, name, public)
values ('dj-sets', 'dj-sets', true)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public;
