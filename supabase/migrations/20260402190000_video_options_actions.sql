-- Video options backend tables for production 3-dots menu actions.
-- - video_favorites
-- - video_remixes
-- - video_qr_events
--
-- Uses TEXT ids for user_id and video_id to match Firebase UID conventions.
-- Idempotent.

DO $$
BEGIN
  IF to_regclass('public.video_favorites') IS NULL THEN
    CREATE TABLE public.video_favorites (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (video_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_video_favorites_video_id ON public.video_favorites (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_favorites_user_id ON public.video_favorites (user_id);
  END IF;

  IF to_regclass('public.video_remixes') IS NULL THEN
    CREATE TABLE public.video_remixes (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      source_video_id text NOT NULL,
      user_id text NOT NULL,
      status text NOT NULL DEFAULT 'draft',
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_video_remixes_source_video_id ON public.video_remixes (source_video_id);
    CREATE INDEX IF NOT EXISTS idx_video_remixes_user_id ON public.video_remixes (user_id);
  END IF;

  IF to_regclass('public.video_qr_events') IS NULL THEN
    CREATE TABLE public.video_qr_events (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      video_id text NOT NULL,
      user_id text,
      event_type text NOT NULL DEFAULT 'qr_opened',
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_video_qr_events_video_id ON public.video_qr_events (video_id);
    CREATE INDEX IF NOT EXISTS idx_video_qr_events_user_id ON public.video_qr_events (user_id);
  END IF;

  ALTER TABLE public.video_favorites ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.video_remixes ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.video_qr_events ENABLE ROW LEVEL SECURITY;

  BEGIN
    DROP POLICY IF EXISTS "public select video_favorites" ON public.video_favorites;
    DROP POLICY IF EXISTS "public insert video_favorites" ON public.video_favorites;
    DROP POLICY IF EXISTS "public delete video_favorites" ON public.video_favorites;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_favorites" ON public.video_favorites
    FOR SELECT USING (true);
  CREATE POLICY "public insert video_favorites" ON public.video_favorites
    FOR INSERT WITH CHECK (true);
  CREATE POLICY "public delete video_favorites" ON public.video_favorites
    FOR DELETE USING (true);

  BEGIN
    DROP POLICY IF EXISTS "public select video_remixes" ON public.video_remixes;
    DROP POLICY IF EXISTS "public insert video_remixes" ON public.video_remixes;
    DROP POLICY IF EXISTS "public update video_remixes" ON public.video_remixes;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_remixes" ON public.video_remixes
    FOR SELECT USING (true);
  CREATE POLICY "public insert video_remixes" ON public.video_remixes
    FOR INSERT WITH CHECK (true);
  CREATE POLICY "public update video_remixes" ON public.video_remixes
    FOR UPDATE USING (true) WITH CHECK (true);

  BEGIN
    DROP POLICY IF EXISTS "public select video_qr_events" ON public.video_qr_events;
    DROP POLICY IF EXISTS "public insert video_qr_events" ON public.video_qr_events;
  EXCEPTION WHEN undefined_object THEN
  END;

  CREATE POLICY "public select video_qr_events" ON public.video_qr_events
    FOR SELECT USING (true);
  CREATE POLICY "public insert video_qr_events" ON public.video_qr_events
    FOR INSERT WITH CHECK (true);

  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
