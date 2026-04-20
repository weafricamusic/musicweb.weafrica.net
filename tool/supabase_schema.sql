-- WeAfrica Music - Supabase schema helpers
--
-- This file is intentionally copy/paste-friendly for the Supabase SQL editor.
-- Apply only the sections you need.

-- =============================================================
-- CREATOR PROFILES (used by role resolver + directories + edit profile)
-- =============================================================
-- Tables read/write in the app:
-- - creator_profiles: role, display_name, avatar_url, bio
--
-- Notes:
-- - `user_id` is the Firebase UID (NOT the Supabase auth user id).
-- - If you enable RLS, you must add policies that match your security model.

create extension if not exists pgcrypto;

do $$
declare
	relkind_char "char";
begin
	select c.relkind
	into relkind_char
	from pg_class c
	join pg_namespace n on n.oid = c.relnamespace
	where n.nspname = 'public'
	  and c.relname = 'creator_profiles'
	limit 1;

	if relkind_char is null then
		create table public.creator_profiles (
			id uuid primary key default gen_random_uuid(),
			user_id text not null unique,
			role text not null check (role in ('artist', 'dj')),
			display_name text not null,
			avatar_url text,
			bio text,
			created_at timestamptz not null default now(),
			updated_at timestamptz not null default now()
		);
	elsif relkind_char <> 'r' then
		raise notice 'public.creator_profiles exists as relkind=% (not a table). Skip table/index/trigger setup. Convert it to a TABLE if you need upsert(on_conflict=user_id).', relkind_char;
		return;
	end if;

	create index if not exists creator_profiles_role_created_at_idx
		on public.creator_profiles (role, created_at desc);

	create or replace function public.set_updated_at()
	returns trigger
	language plpgsql
	as $fn$
	begin
		new.updated_at = now();
		return new;
	end;
	$fn$;

	drop trigger if exists trg_creator_profiles_updated_at on public.creator_profiles;
	create trigger trg_creator_profiles_updated_at
	before update on public.creator_profiles
	for each row execute function public.set_updated_at();
end $$;

-- Optional (security): enable RLS. Only do this if you also add policies.
-- alter table public.creator_profiles enable row level security;
--
-- Example policies (NOT secure for production; use only for testing):
-- create policy "creator_profiles public read" on public.creator_profiles
--   for select using (true);
-- create policy "creator_profiles public write" on public.creator_profiles
--   for insert with check (true);
-- create policy "creator_profiles public update" on public.creator_profiles
--   for update using (true) with check (true);


-- =============================================================
-- AVATARS STORAGE BUCKET (used by Edit Profile avatar upload)
-- =============================================================
-- The app uploads profile images to the bucket named: "avatars".
-- This INSERT typically requires elevated privileges; you can also create it
-- from the Supabase dashboard (Storage → New bucket).

-- create bucket (if not present)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;


-- =============================================================
-- DJ SETS STORAGE BUCKET (used by DJ Dashboard set uploads)
-- =============================================================
-- The app uploads DJ mixes/sets to the bucket named: "dj-sets".
-- If missing, the DJ dashboard upload will fail with "Bucket not found".

insert into storage.buckets (id, name, public)
values ('dj-sets', 'dj-sets', true)
on conflict (id) do update set public = excluded.public;

-- Optional (testing): allow public reads for objects.
-- In production, prefer signed URLs or scoped policies.
-- alter table storage.objects enable row level security;
-- create policy "public avatars read" on storage.objects
--   for select using (bucket_id = 'avatars');

-- Example policy for DJ sets (optional):
-- create policy "public dj-sets read" on storage.objects
--   for select using (bucket_id = 'dj-sets');


-- =============================================================
-- SUBSCRIPTION PLANS CLEANUP (optional but recommended)
-- =============================================================
-- Your `subscription_plans` table appears to contain legacy rows where `plan_id` is NULL.
-- The Edge Function only uses rows where `plan_id` is set.
--
-- To reduce confusion and prevent "maybeSingle" errors in /api/paychangu/start,
-- you can deactivate legacy rows and enforce uniqueness for non-null plan_id.

-- 1) Deactivate legacy rows that cannot be used by the app
update public.subscription_plans
set active = false
where plan_id is null;

-- 2) Prevent duplicate plan_id rows (only for non-null plan_id)
create unique index if not exists subscription_plans_plan_id_unique
on public.subscription_plans (plan_id)
where plan_id is not null;



alter table public.paychangu_payments
	add column if not exists months integer not null default 1;

-- PayChangu: schema drift fixes
-- If Edge Functions return errors like:
--   "Could not find the 'months' column of 'paychangu_payments' in the schema cache"
--   "Could not find the 'tx_ref' column of 'paychangu_payments' in the schema cache"
-- Apply these and then reload the PostgREST schema cache (or restart the API).

alter table public.paychangu_payments
	add column if not exists tx_ref text;

update public.paychangu_payments
set tx_ref = coalesce(tx_ref, gen_random_uuid()::text)
where tx_ref is null;

alter table public.paychangu_payments
	alter column tx_ref set not null;

do $$
begin
	alter table public.paychangu_payments
		add constraint paychangu_payments_tx_ref_key unique (tx_ref);
exception
	when duplicate_object then
		null;
end $$;

-- If you still get:
--   "there is no unique or exclusion constraint matching the ON CONFLICT specification"
-- ensure a UNIQUE INDEX exists too (PostgREST uses this for upsert(on_conflict=tx_ref)).
create unique index if not exists paychangu_payments_tx_ref_uidx
	on public.paychangu_payments (tx_ref);

-- -------------------------------------------------------------
-- NOTE: uid/user_id type drift (uuid vs text)
-- -------------------------------------------------------------
-- Some deployments have `user_id uuid` (often Supabase Auth user id), while this
-- app/Edge Function uses Firebase UID strings.
-- If `user_id` is uuid and `uid` is text, DO NOT run:
--   update ... set user_id = coalesce(user_id, uid)
-- because Postgres will error: COALESCE types uuid and text cannot be matched.
-- Safe backfills:
-- 1) Always safe: copy uuid -> text
--    (keeps uid populated for logging/joins even if user_id is uuid)
--
-- update public.paychangu_payments
-- set uid = coalesce(uid, user_id::text)
-- where uid is null and user_id is not null;
--
-- 2) Only if BOTH columns are text, you can backfill both ways:
--
-- update public.paychangu_payments
-- set user_id = coalesce(user_id, uid)
-- where user_id is null and uid is not null;


-- -------------------------------------------------------------
-- PayChangu: user_id NOT NULL drift fix (prevents HTTP 500)
-- -------------------------------------------------------------
-- Symptom:
--   Edge Function returns HTTP 500 with:
--   "null value in column \"user_id\" of relation \"paychangu_payments\" violates not-null constraint"
--
-- Root cause:
--   Some deployments made `paychangu_payments.user_id` NOT NULL, but the backend
--   uses `uid` (Firebase UID) as the canonical identifier and may not always
--   populate `user_id` on legacy schemas.
--
-- Fix:
-- - Ensure uid/user_id columns exist (text)
-- - Backfill uid from user_id
-- - Drop NOT NULL on user_id (treat it as a compatibility alias)
-- - Add a trigger to coalesce ids on insert/update when types permit

alter table public.paychangu_payments
	add column if not exists uid text;

alter table public.paychangu_payments
	add column if not exists user_id text;

update public.paychangu_payments
set uid = coalesce(uid, user_id::text)
where uid is null
	and user_id is not null;

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

create or replace function public.paychangu_payments_coalesce_ids()
returns trigger
language plpgsql
as $$
declare
	uid_is_uuid boolean := false;
	user_id_is_uuid boolean := false;
begin
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

	if new.uid is null and new.user_id is not null then
		if not uid_is_uuid then
			new.uid := new.user_id::text;
		end if;
	end if;

	if new.user_id is null and new.uid is not null then
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

-- If you still get:
--   "function btrim(uuid) does not exist"
-- it means your DB has a CHECK constraint calling trim()/btrim() on a UUID column
-- (often paychangu_payments.user_id uuid). Drop those constraints:
do $$
declare
	r record;
begin
	for r in (
		select c.conname
		from pg_constraint c
		join pg_class t on t.oid = c.conrelid
		join pg_namespace n on n.oid = t.relnamespace
		where n.nspname = 'public'
			and t.relname = 'paychangu_payments'
			and c.contype = 'c'
			and (
				pg_get_constraintdef(c.oid) ilike '%trim(%user_id%'
				or pg_get_constraintdef(c.oid) ilike '%btrim(%user_id%'
				or pg_get_constraintdef(c.oid) ilike '%trim(user_id%'
				or pg_get_constraintdef(c.oid) ilike '%btrim(user_id%'
			)
	) loop
		execute format('alter table public.paychangu_payments drop constraint if exists %I', r.conname);
	end loop;
exception
	when undefined_table then
		null;
end $$;



