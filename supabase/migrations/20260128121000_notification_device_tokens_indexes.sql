-- Improve filtering performance for push token registry.

create index if not exists notification_device_tokens_country_code_idx
  on public.notification_device_tokens (country_code);
create index if not exists notification_device_tokens_last_seen_at_idx
  on public.notification_device_tokens (last_seen_at desc);
-- Speeds up jsonb @> (contains) queries like: topics @> '["marketing"]'
create index if not exists notification_device_tokens_topics_gin_idx
  on public.notification_device_tokens using gin (topics);
