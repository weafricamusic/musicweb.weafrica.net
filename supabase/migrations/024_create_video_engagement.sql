-- Video engagement tables used by Pulse (likes, comments, shares).
-- Uses TEXT ids for `user_id` (Firebase UID) and `video_id` (string-safe).
-- Idempotent.

DO $$
BEGIN
  IF to_regclass('public.video_likes') IS NULL THEN
    CREATE TABLE public.video_likes (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (video_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_video_likes_video_id ON public.video_likes (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_likes_user_id ON public.video_likes (user_id);
  END IF;

  IF to_regclass('public.video_comments') IS NULL THEN
    CREATE TABLE public.video_comments (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text NOT NULL,
      comment text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_video_comments_video_id ON public.video_comments (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_comments_user_id ON public.video_comments (user_id);
  END IF;

  IF to_regclass('public.video_shares') IS NULL THEN
    CREATE TABLE public.video_shares (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_video_shares_video_id ON public.video_shares (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_shares_user_id ON public.video_shares (user_id);
  END IF;

  -- MVP RLS: public read/write like the other MVP tables.
  ALTER TABLE public.video_likes ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.video_comments ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.video_shares ENABLE ROW LEVEL SECURITY;

  BEGIN
    DROP POLICY IF EXISTS "public select video_likes" ON public.video_likes;
    DROP POLICY IF EXISTS "public insert video_likes" ON public.video_likes;
    DROP POLICY IF EXISTS "public delete video_likes" ON public.video_likes;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_likes" ON public.video_likes
    FOR SELECT USING (true);

  CREATE POLICY "public insert video_likes" ON public.video_likes
    FOR INSERT WITH CHECK (true);

  CREATE POLICY "public delete video_likes" ON public.video_likes
    FOR DELETE USING (true);

  BEGIN
    DROP POLICY IF EXISTS "public select video_comments" ON public.video_comments;
    DROP POLICY IF EXISTS "public insert video_comments" ON public.video_comments;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_comments" ON public.video_comments
    FOR SELECT USING (true);

  CREATE POLICY "public insert video_comments" ON public.video_comments
    FOR INSERT WITH CHECK (true);

  BEGIN
    DROP POLICY IF EXISTS "public select video_shares" ON public.video_shares;
    DROP POLICY IF EXISTS "public insert video_shares" ON public.video_shares;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_shares" ON public.video_shares
    FOR SELECT USING (true);

  CREATE POLICY "public insert video_shares" ON public.video_shares
    FOR INSERT WITH CHECK (true);

  -- Ask PostgREST to reload schema cache.
  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
