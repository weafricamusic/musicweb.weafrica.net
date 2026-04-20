-- Fix: Firebase UIDs are NOT UUIDs.
--
-- Some deployments accidentally created `paychangu_payments.user_id` (or even `uid`) as UUID
-- (often via `references auth.users(id)`), but this project uses Firebase Auth UIDs.
-- Those identifiers look like: mFoJJ0BgkvRlqkyzAlgZlt7t0V92
-- which cannot be cast to uuid.
--
-- This migration safely converts those columns to `text`.

do $$
declare
  user_id_attnum int;
  uid_attnum int;
  r record;
  user_id_type text;
  uid_type text;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'paychangu_payments'
  ) then
    return;
  end if;

  select c.udt_name
  into user_id_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'paychangu_payments'
    and c.column_name = 'user_id'
  limit 1;

  select c.udt_name
  into uid_type
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'paychangu_payments'
    and c.column_name = 'uid'
  limit 1;

  -- Drop foreign keys that reference paychangu_payments.user_id (if any).
  if user_id_type = 'uuid' then
    select a.attnum
    into user_id_attnum
    from pg_attribute a
    where a.attrelid = 'public.paychangu_payments'::regclass
      and a.attname = 'user_id'
      and a.attisdropped = false
    limit 1;

    for r in (
      select c.conname
      from pg_constraint c
      where c.conrelid = 'public.paychangu_payments'::regclass
        and c.contype = 'f'
        and user_id_attnum = any (c.conkey)
    ) loop
      execute format('alter table public.paychangu_payments drop constraint if exists %I', r.conname);
    end loop;

    -- Make nullable before conversion (avoids edge cases with NOT NULL + bad legacy data).
    begin
      execute 'alter table public.paychangu_payments alter column user_id drop not null';
    exception
      when others then
        null;
    end;

    execute 'alter table public.paychangu_payments alter column user_id type text using user_id::text';
  end if;

  -- Very defensive: if uid was also created as uuid, convert it too.
  if uid_type = 'uuid' then
    select a.attnum
    into uid_attnum
    from pg_attribute a
    where a.attrelid = 'public.paychangu_payments'::regclass
      and a.attname = 'uid'
      and a.attisdropped = false
    limit 1;

    for r in (
      select c.conname
      from pg_constraint c
      where c.conrelid = 'public.paychangu_payments'::regclass
        and c.contype = 'f'
        and uid_attnum = any (c.conkey)
    ) loop
      execute format('alter table public.paychangu_payments drop constraint if exists %I', r.conname);
    end loop;

    begin
      execute 'alter table public.paychangu_payments alter column uid drop not null';
    exception
      when others then
        null;
    end;

    execute 'alter table public.paychangu_payments alter column uid type text using uid::text';
  end if;
end $$;

notify pgrst, 'reload schema';
