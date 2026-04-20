-- Compatibility migration: older deployments used public.paychangu_payments
-- and stored the purchased duration in a dedicated `months` column.
--
-- Newer code paths store interval metadata in JSONB (meta) and/or use
-- public.subscription_payments.
--
-- This migration is safe to run even if paychangu_payments does not exist.

alter table if exists public.paychangu_payments
  add column if not exists months integer;

-- Hint PostgREST to refresh its schema cache quickly.
-- (Safe if PostgREST isn't listening; it will simply be ignored.)
notify pgrst, 'reload schema';
