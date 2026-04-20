-- Fix schema drift: ensure paychangu_payments has the columns expected by the Edge Function.
--
-- Error observed from /api/paychangu/start:
--   "Could not find the 'months' column of 'paychangu_payments' in the schema cache"

alter table public.paychangu_payments
  add column if not exists months integer not null default 1;

-- Defensive: older deployments sometimes used different names; keep the canonical one.
-- (No-op if columns already exist.)
alter table public.paychangu_payments
  add column if not exists checkout_url text;

alter table public.paychangu_payments
  add column if not exists raw jsonb;
