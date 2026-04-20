-- Add FCM token storage on users for compatibility with invite/push lookups.

alter table if exists public.users
  add column if not exists fcm_token text;

create index if not exists users_fcm_token_idx
  on public.users (fcm_token)
  where fcm_token is not null;
