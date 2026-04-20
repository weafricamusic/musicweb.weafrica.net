-- Add a lightweight idempotency key to live chat messages.
-- Used to prevent duplicate system events like "<user> joined" being inserted multiple times
-- if the UI/controller restarts.

alter table public.live_messages
  add column if not exists dedupe_key text;

create unique index if not exists live_messages_live_dedupe_key_uidx
  on public.live_messages (live_id, dedupe_key)
  where dedupe_key is not null;
