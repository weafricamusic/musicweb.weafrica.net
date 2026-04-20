-- Video personalization tables used by Pulse "More" menu.
--
-- - video_saves: user bookmarks (Save)
-- - video_not_interested: hide videos from feed (Not interested)
--
-- Uses TEXT ids for `user_id` (Firebase UID) and `video_id` (string-safe).
-- Idempotent.

DO $$
BEGIN
  IF to_regclass('public.video_saves') IS NULL THEN
    CREATE TABLE public.video_saves (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (video_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_video_saves_video_id ON public.video_saves (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_saves_user_id ON public.video_saves (user_id);
  END IF;

  IF to_regclass('public.video_not_interested') IS NULL THEN
    CREATE TABLE public.video_not_interested (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (video_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_video_not_interested_video_id ON public.video_not_interested (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_not_interested_user_id ON public.video_not_interested (user_id);
  END IF;

  -- MVP RLS: public read/write like the other MVP engagement tables.
  ALTER TABLE public.video_saves ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.video_not_interested ENABLE ROW LEVEL SECURITY;

  BEGIN
    DROP POLICY IF EXISTS "public select video_saves" ON public.video_saves;
    DROP POLICY IF EXISTS "public insert video_saves" ON public.video_saves;
    DROP POLICY IF EXISTS "public delete video_saves" ON public.video_saves;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_saves" ON public.video_saves
    FOR SELECT USING (true);

  CREATE POLICY "public insert video_saves" ON public.video_saves
    FOR INSERT WITH CHECK (true);

  CREATE POLICY "public delete video_saves" ON public.video_saves
    FOR DELETE USING (true);

  BEGIN
    DROP POLICY IF EXISTS "public select video_not_interested" ON public.video_not_interested;
    DROP POLICY IF EXISTS "public insert video_not_interested" ON public.video_not_interested;
    DROP POLICY IF EXISTS "public delete video_not_interested" ON public.video_not_interested;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_not_interested" ON public.video_not_interested
    FOR SELECT USING (true);

  CREATE POLICY "public insert video_not_interested" ON public.video_not_interested
    FOR INSERT WITH CHECK (true);

  CREATE POLICY "public delete video_not_interested" ON public.video_not_interested
    FOR DELETE USING (true);

  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
