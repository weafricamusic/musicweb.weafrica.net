-- Real engagement storage for photo + song posts.

CREATE TABLE IF NOT EXISTS public.photo_song_post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.photo_song_posts(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.photo_song_post_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.photo_song_posts(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT photo_song_post_comments_content_not_blank CHECK (length(trim(content)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_photo_song_post_likes_post_id
  ON public.photo_song_post_likes(post_id);

CREATE INDEX IF NOT EXISTS idx_photo_song_post_likes_user_id
  ON public.photo_song_post_likes(user_id);

CREATE INDEX IF NOT EXISTS idx_photo_song_post_comments_post_id
  ON public.photo_song_post_comments(post_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_photo_song_post_comments_user_id
  ON public.photo_song_post_comments(user_id);

CREATE OR REPLACE FUNCTION public.refresh_photo_song_post_likes_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_post_id uuid;
BEGIN
  v_post_id := COALESCE(NEW.post_id, OLD.post_id);

  UPDATE public.photo_song_posts
  SET likes_count = (
    SELECT count(*)::integer
    FROM public.photo_song_post_likes l
    WHERE l.post_id = v_post_id
  ),
  updated_at = now()
  WHERE id = v_post_id;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_photo_song_post_comments_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_post_id uuid;
BEGIN
  v_post_id := COALESCE(NEW.post_id, OLD.post_id);

  UPDATE public.photo_song_posts
  SET comments_count = (
    SELECT count(*)::integer
    FROM public.photo_song_post_comments c
    WHERE c.post_id = v_post_id
  ),
  updated_at = now()
  WHERE id = v_post_id;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_photo_song_post_likes_refresh_count ON public.photo_song_post_likes;
CREATE TRIGGER trg_photo_song_post_likes_refresh_count
AFTER INSERT OR DELETE ON public.photo_song_post_likes
FOR EACH ROW EXECUTE FUNCTION public.refresh_photo_song_post_likes_count();

DROP TRIGGER IF EXISTS trg_photo_song_post_comments_refresh_count ON public.photo_song_post_comments;
CREATE TRIGGER trg_photo_song_post_comments_refresh_count
AFTER INSERT OR DELETE ON public.photo_song_post_comments
FOR EACH ROW EXECUTE FUNCTION public.refresh_photo_song_post_comments_count();

ALTER TABLE public.photo_song_post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photo_song_post_comments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN
    CREATE POLICY "photo_song_post_likes read" ON public.photo_song_post_likes
      FOR SELECT
      TO anon, authenticated
      USING (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    CREATE POLICY "photo_song_post_likes insert" ON public.photo_song_post_likes
      FOR INSERT
      TO anon, authenticated
      WITH CHECK (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    CREATE POLICY "photo_song_post_likes delete" ON public.photo_song_post_likes
      FOR DELETE
      TO anon, authenticated
      USING (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    CREATE POLICY "photo_song_post_comments read" ON public.photo_song_post_comments
      FOR SELECT
      TO anon, authenticated
      USING (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;

  BEGIN
    CREATE POLICY "photo_song_post_comments insert" ON public.photo_song_post_comments
      FOR INSERT
      TO anon, authenticated
      WITH CHECK (true);
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;
END $$;

GRANT SELECT, INSERT, DELETE ON TABLE public.photo_song_post_likes TO anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.photo_song_post_comments TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
