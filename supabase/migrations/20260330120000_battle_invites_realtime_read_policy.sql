-- Enable Realtime delivery for battle_invites (recipient-only).
--
-- This is for Firebase-auth clients that subscribe via Supabase Realtime using
-- a short-lived JWT minted by the Edge API (/api/realtime/token).
--
-- Important:
-- - battle_invites is RLS deny-all by default; we add an explicit SELECT policy.
-- - Policies should use auth.jwt() ->> 'sub' (TEXT Firebase UID), not auth.uid().

-- 1) Ensure the table is part of the Realtime publication.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'battle_invites'
    ) THEN
      EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.battle_invites';
    END IF;
  END IF;
END $$;

-- 2) Allow authenticated role to SELECT its own invites.
-- Note: battle_invites was revoked from anon/authenticated in earlier migrations.
GRANT SELECT ON TABLE public.battle_invites TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'battle_invites'
      AND policyname = 'battle_invites_select_own_inbox'
  ) THEN
    CREATE POLICY battle_invites_select_own_inbox
      ON public.battle_invites
      FOR SELECT
      TO authenticated
      USING (
        -- Prefer canonical column when available.
        (
          (to_uid IS NOT NULL AND LENGTH(BTRIM(to_uid)) > 0 AND BTRIM(to_uid) = (auth.jwt() ->> 'sub'))
          OR
          (to_artist_uid IS NOT NULL AND LENGTH(BTRIM(to_artist_uid)) > 0 AND BTRIM(to_artist_uid) = (auth.jwt() ->> 'sub'))
        )
      );
  END IF;
END $$;
