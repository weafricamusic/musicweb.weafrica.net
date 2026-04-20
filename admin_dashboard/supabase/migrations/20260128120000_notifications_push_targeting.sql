-- Extend push messages with token targeting (country/role/topic/user).

alter table public.notification_push_messages
  add column if not exists delivery text not null default 'fcm_topic'
    check (delivery in ('tokens','fcm_topic')),
  add column if not exists token_topic text,
  add column if not exists target_country_code text,
  add column if not exists target_role text
    check (target_role is null or target_role in ('consumers','artists','djs')),
  add column if not exists target_user_uid text;

-- Backfill: old rows used topic='tokens_all' to mean token broadcast.
update public.notification_push_messages
set delivery = 'tokens'
where topic = 'tokens_all';

create index if not exists notification_push_messages_delivery_created_at_idx
  on public.notification_push_messages (delivery, created_at desc);

create index if not exists notification_push_messages_token_target_idx
  on public.notification_push_messages (token_topic, target_country_code, target_role, created_at desc);
