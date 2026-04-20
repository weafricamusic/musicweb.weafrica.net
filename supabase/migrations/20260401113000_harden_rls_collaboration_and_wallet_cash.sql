-- Production hardening: remove MVP allow-all RLS on sensitive tables.
--
-- Targets:
-- - public.collaboration_invites
-- - public.wallet_cash_balances
--
-- This migration is idempotent and safe to re-run.

DO $$
DECLARE
  r RECORD;
BEGIN
  -- collaboration_invites
  IF to_regclass('public.collaboration_invites') IS NOT NULL THEN
    ALTER TABLE public.collaboration_invites ENABLE ROW LEVEL SECURITY;

    FOR r IN (
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'collaboration_invites'
    ) LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.collaboration_invites', r.policyname);
    END LOOP;

    CREATE POLICY collaboration_invites_select_participants
      ON public.collaboration_invites
      FOR SELECT
      TO authenticated
      USING (auth.uid()::text = from_uid OR auth.uid()::text = to_uid);

    CREATE POLICY collaboration_invites_insert_sender
      ON public.collaboration_invites
      FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid()::text = from_uid);

    CREATE POLICY collaboration_invites_update_participants
      ON public.collaboration_invites
      FOR UPDATE
      TO authenticated
      USING (auth.uid()::text = from_uid OR auth.uid()::text = to_uid)
      WITH CHECK (auth.uid()::text = from_uid OR auth.uid()::text = to_uid);

    CREATE POLICY collaboration_invites_delete_sender
      ON public.collaboration_invites
      FOR DELETE
      TO authenticated
      USING (auth.uid()::text = from_uid);

    REVOKE ALL ON TABLE public.collaboration_invites FROM anon;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.collaboration_invites TO authenticated;
  END IF;

  -- wallet_cash_balances
  IF to_regclass('public.wallet_cash_balances') IS NOT NULL THEN
    ALTER TABLE public.wallet_cash_balances ENABLE ROW LEVEL SECURITY;

    FOR r IN (
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'wallet_cash_balances'
    ) LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.wallet_cash_balances', r.policyname);
    END LOOP;

    CREATE POLICY wallet_cash_balances_select_own
      ON public.wallet_cash_balances
      FOR SELECT
      TO authenticated
      USING (auth.uid()::text = user_id);

    CREATE POLICY wallet_cash_balances_insert_own
      ON public.wallet_cash_balances
      FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid()::text = user_id);

    CREATE POLICY wallet_cash_balances_update_own
      ON public.wallet_cash_balances
      FOR UPDATE
      TO authenticated
      USING (auth.uid()::text = user_id)
      WITH CHECK (auth.uid()::text = user_id);

    CREATE POLICY wallet_cash_balances_delete_own
      ON public.wallet_cash_balances
      FOR DELETE
      TO authenticated
      USING (auth.uid()::text = user_id);

    REVOKE ALL ON TABLE public.wallet_cash_balances FROM anon;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.wallet_cash_balances TO authenticated;
  END IF;

  PERFORM pg_notify('pgrst', 'reload schema');
END $$;