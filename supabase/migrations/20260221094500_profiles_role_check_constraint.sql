-- Lock down `profiles.role` to a known set of values.
-- This prevents accidental writes like 'Consumer', 'listener', null, etc.
--
-- Allowed roles: consumer, artist, dj, admin (future)

DO $$
BEGIN
  IF to_regclass('public.profiles') IS NOT NULL THEN
    -- Normalize any legacy values before enforcing the constraint.
    UPDATE public.profiles
      SET role = lower(btrim(role))
      WHERE role IS NOT NULL AND role <> lower(btrim(role));

    -- If the constraint already exists, skip.
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'profiles_role_valid'
        AND conrelid = 'public.profiles'::regclass
    ) THEN
      ALTER TABLE public.profiles
        ADD CONSTRAINT profiles_role_valid
        CHECK (role IN ('consumer', 'artist', 'dj', 'admin'));
    END IF;
  END IF;
END $$;
