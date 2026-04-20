-- MVP RLS policies to unblock client inserts/selects on media tables.
--
-- SECURITY WARNING:
-- This makes `songs` and `videos` publicly readable and writable (anon).
-- Use ONLY for development/MVP.
-- Production options:
--  - Use Supabase Auth so `auth.uid()` is meaningful, or
--  - Use an Edge Function / server with service-role and signed uploads.

DO $$
BEGIN
  IF to_regclass('public.songs') IS NOT NULL THEN
    ALTER TABLE public.songs ENABLE ROW LEVEL SECURITY;

    -- Drop then recreate (idempotent-ish for repeated runs).
    BEGIN
      DROP POLICY IF EXISTS "public select songs" ON public.songs;
      DROP POLICY IF EXISTS "public insert songs" ON public.songs;
      DROP POLICY IF EXISTS "public update songs" ON public.songs;
      DROP POLICY IF EXISTS "public delete songs" ON public.songs;
    EXCEPTION WHEN undefined_object THEN
      -- ignore
    END;

    CREATE POLICY "public select songs" ON public.songs
      FOR SELECT USING (true);

    CREATE POLICY "public insert songs" ON public.songs
      FOR INSERT WITH CHECK (true);

    CREATE POLICY "public update songs" ON public.songs
      FOR UPDATE USING (true) WITH CHECK (true);

    CREATE POLICY "public delete songs" ON public.songs
      FOR DELETE USING (true);
  END IF;

  IF to_regclass('public.videos') IS NOT NULL THEN
    ALTER TABLE public.videos ENABLE ROW LEVEL SECURITY;

    BEGIN
      DROP POLICY IF EXISTS "public select videos" ON public.videos;
      DROP POLICY IF EXISTS "public insert videos" ON public.videos;
      DROP POLICY IF EXISTS "public update videos" ON public.videos;
      DROP POLICY IF EXISTS "public delete videos" ON public.videos;
    EXCEPTION WHEN undefined_object THEN
      -- ignore
    END;

    CREATE POLICY "public select videos" ON public.videos
      FOR SELECT USING (true);

    CREATE POLICY "public insert videos" ON public.videos
      FOR INSERT WITH CHECK (true);

    CREATE POLICY "public update videos" ON public.videos
      FOR UPDATE USING (true) WITH CHECK (true);

    CREATE POLICY "public delete videos" ON public.videos
      FOR DELETE USING (true);
  END IF;
END $$;
