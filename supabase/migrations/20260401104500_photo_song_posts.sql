-- Instagram-style picture + song posts (MVP)
-- Creates table + storage bucket used by Flutter photo-song composer.

CREATE TABLE IF NOT EXISTS public.photo_song_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_uid text NOT NULL,
  image_url text NOT NULL,
  song_id uuid NOT NULL REFERENCES public.songs(id) ON DELETE RESTRICT,
  song_start integer NOT NULL DEFAULT 0,
  song_duration integer NOT NULL DEFAULT 15,
  caption text,
  likes_count integer NOT NULL DEFAULT 0,
  comments_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT photo_song_posts_song_start_non_negative CHECK (song_start >= 0),
  CONSTRAINT photo_song_posts_song_duration_bounds CHECK (song_duration BETWEEN 5 AND 60),
  CONSTRAINT photo_song_posts_likes_non_negative CHECK (likes_count >= 0),
  CONSTRAINT photo_song_posts_comments_non_negative CHECK (comments_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_photo_song_posts_created_at
  ON public.photo_song_posts (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_photo_song_posts_creator_uid
  ON public.photo_song_posts (creator_uid);

ALTER TABLE public.photo_song_posts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN
    CREATE POLICY "photo_song_posts read" ON public.photo_song_posts
      FOR SELECT
      TO anon, authenticated
      USING (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    CREATE POLICY "photo_song_posts insert" ON public.photo_song_posts
      FOR INSERT
      TO anon, authenticated
      WITH CHECK (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;
END $$;

GRANT SELECT, INSERT ON TABLE public.photo_song_posts TO anon, authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'post_images',
  'post_images',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  BEGIN
    CREATE POLICY "post_images public read" ON storage.objects
      FOR SELECT
      TO anon, authenticated
      USING (bucket_id = 'post_images');
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    CREATE POLICY "post_images upload" ON storage.objects
      FOR INSERT
      TO anon, authenticated
      WITH CHECK (bucket_id = 'post_images');
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;
END $$;

SELECT pg_notify('pgrst', 'reload schema');
