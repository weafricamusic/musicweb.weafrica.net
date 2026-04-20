-- Optional metadata for device token registry (helps debugging/analytics)

alter table public.notification_device_tokens
  add column if not exists app_version text,
  add column if not exists device_model text,
  add column if not exists locale text;
create index if not exists notification_device_tokens_country_code_idx
  on public.notification_device_tokens (country_code);
