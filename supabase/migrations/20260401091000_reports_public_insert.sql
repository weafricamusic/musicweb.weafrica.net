-- Allow clients to submit reports while keeping reports non-readable.
--
-- The moderation core migration defaults to deny-all RLS on public.reports.
-- This adds an INSERT policy and grant for anon/authenticated so the app can
-- submit reports (e.g. from Pulse "Report" action). Reads remain blocked by
-- the existing deny policy.

DO $$
BEGIN
  IF to_regclass('public.reports') IS NOT NULL THEN
    ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

    BEGIN
      CREATE POLICY "public insert reports" ON public.reports
        FOR INSERT
        TO anon, authenticated
        WITH CHECK (
          content_type IN ('video', 'song', 'album', 'live_session', 'battle', 'comment', 'user', 'playlist')
          AND nullif(btrim(content_id), '') IS NOT NULL
          AND nullif(btrim(reason), '') IS NOT NULL
          AND (reporter_id IS NULL OR nullif(btrim(reporter_id), '') IS NOT NULL)
        );
    EXCEPTION
      WHEN duplicate_object THEN
        ALTER POLICY "public insert reports"
          ON public.reports
          TO anon, authenticated
          WITH CHECK (
            content_type IN ('video', 'song', 'album', 'live_session', 'battle', 'comment', 'user', 'playlist')
            AND nullif(btrim(content_id), '') IS NOT NULL
            AND nullif(btrim(reason), '') IS NOT NULL
            AND (reporter_id IS NULL OR nullif(btrim(reporter_id), '') IS NOT NULL)
          );
    END;

    GRANT INSERT ON TABLE public.reports TO anon, authenticated;
  END IF;

  PERFORM pg_notify('pgrst', 'reload schema');
END $$;
