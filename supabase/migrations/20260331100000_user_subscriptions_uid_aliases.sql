-- Compatibility migration: align `public.user_subscriptions` uid columns.
--
-- Problem:
-- - Older Edge builds query `user_subscriptions.user_uid` or `user_id`.
-- - Newer schema versions may only have `uid` (or legacy append-only table has `user_id`).
--
-- Fix:
-- - Ensure `uid`, `user_id`, and `user_uid` columns all exist.
-- - Keep them populated consistently so API queries do not error/fallback.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_subscriptions'
      and column_name = 'uid'
  ) then
    alter table public.user_subscriptions add column uid text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_subscriptions'
      and column_name = 'user_id'
  ) then
    alter table public.user_subscriptions add column user_id text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_subscriptions'
      and column_name = 'user_uid'
  ) then
    alter table public.user_subscriptions add column user_uid text;
  end if;
end $$;

-- Best-effort backfill for existing rows.
update public.user_subscriptions
set
  uid = coalesce(nullif(uid, ''), nullif(user_id, ''), nullif(user_uid, '')),
  user_id = coalesce(nullif(user_id, ''), nullif(uid, ''), nullif(user_uid, '')),
  user_uid = coalesce(nullif(user_uid, ''), nullif(uid, ''), nullif(user_id, ''));

create index if not exists user_subscriptions_uid_idx on public.user_subscriptions (uid);
create index if not exists user_subscriptions_user_uid_idx on public.user_subscriptions (user_uid);

create or replace function public.sync_user_subscription_uid_columns()
returns trigger
language plpgsql
as $$
begin
  if new.uid is null or length(btrim(new.uid)) = 0 then
    new.uid := nullif(coalesce(new.user_id, new.user_uid, new.uid), '');
  end if;

  if new.user_id is null or length(btrim(new.user_id)) = 0 then
    new.user_id := nullif(coalesce(new.uid, new.user_uid, new.user_id), '');
  end if;

  if new.user_uid is null or length(btrim(new.user_uid)) = 0 then
    new.user_uid := nullif(coalesce(new.uid, new.user_id, new.user_uid), '');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_user_subscription_uid_columns on public.user_subscriptions;
create trigger trg_sync_user_subscription_uid_columns
before insert or update on public.user_subscriptions
for each row execute function public.sync_user_subscription_uid_columns();
