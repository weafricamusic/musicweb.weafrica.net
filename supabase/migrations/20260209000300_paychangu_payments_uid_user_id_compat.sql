-- Compatibility migration: support both `uid` and `user_id` column names.
--
-- Different deployments historically used either:
--  - uid (Firebase UID)
--  - user_id (same value)
--
-- The Edge Function now writes both to tolerate drift, but this migration
-- reduces runtime errors by ensuring both columns exist.

do $$
declare
  has_uid boolean;
  has_user_id boolean;
  uid_type text;
  user_id_type text;
begin
  select exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'paychangu_payments'
      and column_name = 'uid'
  ) into has_uid;

  select exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'paychangu_payments'
      and column_name = 'user_id'
  ) into has_user_id;

  if not has_uid then
    execute 'alter table public.paychangu_payments add column if not exists uid text';
  end if;

  if not has_user_id then
    execute 'alter table public.paychangu_payments add column if not exists user_id text';
  end if;

  -- Determine column types (can differ across deployments, e.g. user_id uuid vs uid text).
  select c.udt_name
  into uid_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'paychangu_payments'
    and c.column_name = 'uid'
  limit 1;

  select c.udt_name
  into user_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'paychangu_payments'
    and c.column_name = 'user_id'
  limit 1;

  -- Backfill in the safe direction based on types.
  -- - If user_id is uuid and uid is text: we can always backfill uid from user_id::text.
  --   We must NOT try to backfill user_id from uid (Firebase UIDs are not UUIDs).
  -- - If both are text: we can backfill both ways.
  -- - If uid is uuid and user_id is text: backfill user_id from uid::text.

  if (user_id_type = 'uuid' and uid_type <> 'uuid') then
    execute 'update public.paychangu_payments set uid = coalesce(uid, user_id::text)';
  elsif (uid_type = 'uuid' and user_id_type <> 'uuid') then
    execute 'update public.paychangu_payments set user_id = coalesce(user_id, uid::text)';
  else
    -- Same type (commonly both text)
    execute 'update public.paychangu_payments set user_id = coalesce(user_id, uid)';
    execute 'update public.paychangu_payments set uid = coalesce(uid, user_id)';
  end if;
end $$;

create index if not exists paychangu_payments_uid_idx_compat on public.paychangu_payments(uid);
create index if not exists paychangu_payments_user_id_idx_compat on public.paychangu_payments(user_id);
