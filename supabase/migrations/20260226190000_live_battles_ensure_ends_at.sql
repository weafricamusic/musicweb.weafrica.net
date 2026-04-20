-- Ensure live_battles has ends_at (compat)
--
-- Some environments may have the battle invite RPC deployed (which inserts into
-- live_battles.ends_at) before applying the STEP 4 migration that adds the
-- column. That results in HTTP 500s during battle invite/schedule.
--
-- This migration is safe + idempotent.

-- Needed for gen_random_uuid() on some setups (used widely across schema)
create extension if not exists pgcrypto;

alter table public.live_battles
  add column if not exists ends_at timestamptz;
