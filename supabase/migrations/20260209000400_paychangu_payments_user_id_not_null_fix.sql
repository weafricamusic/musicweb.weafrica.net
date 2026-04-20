-- Safety migration: avoid runtime failures when deployments have `paychangu_payments.user_id NOT NULL`
-- but the backend writes `uid` (Firebase UID) as the canonical identifier.
--
-- Goal:
-- - Make `user_id` a nullable compatibility column (alias of `uid`).
-- - Backfill `uid` from `user_id` when safe.
-- - Add a trigger to coalesce ids on insert/update when types permit.

-- 1) Ensure compatibility columns exist (no-ops if already present)
alter table public.paychangu_payments
  add column if not exists uid text;

alter table public.paychangu_payments
  add column if not exists user_id text;

-- 2) Backfill in the safe direction(s)
-- Always safe: copy user_id -> uid as text
update public.paychangu_payments
set uid = coalesce(uid, user_id::text)
where uid is null
  and user_id is not null;

-- 3) Make user_id nullable (some older schemas made it NOT NULL)
do $$
begin
  if exists(
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'paychangu_payments'
      and c.column_name = 'user_id'
      and c.is_nullable = 'NO'
  ) then
    execute 'alter table public.paychangu_payments alter column user_id drop not null';
  end if;
exception
  when undefined_table then
    null;
end $$;

-- 4) Coalesce ids for new writes (best effort; skips unsafe uuid assignments)
create or replace function public.paychangu_payments_coalesce_ids()
returns trigger
language plpgsql
as $$
declare
  uid_is_uuid boolean := false;
  user_id_is_uuid boolean := false;
begin
  -- Determine column types from catalog (works even when NEW values are NULL).
  begin
    select (a.atttypid = 'uuid'::regtype)
    into uid_is_uuid
    from pg_attribute a
    where a.attrelid = 'public.paychangu_payments'::regclass
      and a.attname = 'uid'
      and a.attisdropped = false
    limit 1;
  exception
    when undefined_table then
      uid_is_uuid := false;
  end;

  begin
    select (a.atttypid = 'uuid'::regtype)
    into user_id_is_uuid
    from pg_attribute a
    where a.attrelid = 'public.paychangu_payments'::regclass
      and a.attname = 'user_id'
      and a.attisdropped = false
    limit 1;
  exception
    when undefined_table then
      user_id_is_uuid := false;
  end;

  -- Prefer keeping uid populated.
  if new.uid is null and new.user_id is not null then
    -- If uid is uuid, skip (Firebase UIDs are not UUIDs).
    if not uid_is_uuid then
      new.uid := new.user_id::text;
    end if;
  end if;

  if new.user_id is null and new.uid is not null then
    -- If user_id is uuid, skip.
    if not user_id_is_uuid then
      new.user_id := new.uid::text;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_paychangu_payments_coalesce_ids on public.paychangu_payments;
create trigger trg_paychangu_payments_coalesce_ids
before insert or update on public.paychangu_payments
for each row execute function public.paychangu_payments_coalesce_ids();

-- 5) Helpful indexes (no-ops if they exist)
create index if not exists paychangu_payments_uid_idx_compat on public.paychangu_payments(uid);
create index if not exists paychangu_payments_user_id_idx_compat on public.paychangu_payments(user_id);
