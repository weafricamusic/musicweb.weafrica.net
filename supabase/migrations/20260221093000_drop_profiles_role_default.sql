-- Ensure roles are always explicit.
--
-- We use Firebase Auth (not Supabase Auth), and profile provisioning happens
-- via Edge endpoints. A DEFAULT on profiles.role can silently overwrite role
-- intent for newly created users.
--
-- This migration drops the DEFAULT (if present) and backfills any NULL/blank
-- roles to 'consumer' to keep rows valid.

DO $$
BEGIN
  IF to_regclass('public.profiles') IS NOT NULL
     AND EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name = 'role'
    )
  THEN
    -- Drop the default so every insert must provide an explicit role.
    EXECUTE 'ALTER TABLE public.profiles ALTER COLUMN role DROP DEFAULT';

    -- Defensive cleanup for any legacy rows.
    UPDATE public.profiles
      SET role = 'consumer'
      WHERE role IS NULL OR btrim(role) = '';
  END IF;
END $$;
