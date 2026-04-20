-- Final schema alignment for WeAfrica core + safety principles.
-- Goal: one source of truth, no hard deletes, status-based control, full traceability.

create extension if not exists pgcrypto;

-- 1) USERS
alter table public.users
  add column if not exists firebase_uid text,
  add column if not exists username text,
  add column if not exists email text,
  add column if not exists avatar_url text,
  add column if not exists status text not null default 'active',
  add column if not exists region text not null default 'MW',
  add column if not exists created_at timestamptz not null default now();

-- Enforce allowed statuses (non-breaking: only adds constraint if absent).
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'users_status_check'
  ) then
    alter table public.users
      add constraint users_status_check
      check (status in ('active','blocked'));
  end if;
end $$;

create unique index if not exists users_firebase_uid_unique on public.users (firebase_uid);
create index if not exists users_status_idx on public.users (status);

-- 2) ARTISTS
alter table public.artists
  add column if not exists firebase_uid text,
  add column if not exists stage_name text,
  add column if not exists email text,
  add column if not exists bio text,
  add column if not exists profile_image text,
  add column if not exists status text not null default 'pending',
  add column if not exists verified boolean not null default false,
  add column if not exists can_upload boolean not null default false,
  add column if not exists can_go_live boolean not null default false,
  add column if not exists region text not null default 'MW',
  add column if not exists created_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'artists_status_check'
  ) then
    alter table public.artists
      add constraint artists_status_check
      check (status in ('pending','active','blocked'));
  end if;
end $$;

create unique index if not exists artists_firebase_uid_unique on public.artists (firebase_uid);
create index if not exists artists_status_idx on public.artists (status);

-- 3) DJS
alter table public.djs
  add column if not exists firebase_uid text,
  add column if not exists dj_name text,
  add column if not exists email text,
  add column if not exists profile_image text,
  add column if not exists status text not null default 'pending',
  add column if not exists can_go_live boolean not null default false,
  add column if not exists region text not null default 'MW',
  add column if not exists created_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'djs_status_check'
  ) then
    alter table public.djs
      add constraint djs_status_check
      check (status in ('pending','active','blocked'));
  end if;
end $$;

create unique index if not exists djs_firebase_uid_unique on public.djs (firebase_uid);
create index if not exists djs_status_idx on public.djs (status);

-- 4) SONGS (soft-remove via status; keep existing flags for compatibility)
-- Canonical: status = active|removed
alter table public.songs
  add column if not exists status text not null default 'active',
  add column if not exists streams integer not null default 0;

do $$
begin
  -- Normalize any legacy/invalid statuses before enforcing the constraint.
  begin
    update public.songs
      set status = 'active'
      where status is null
         or status not in ('active','removed');
  exception
    when undefined_table then null;
    when undefined_column then null;
  end;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'songs_status_check'
  ) then
    alter table public.songs
      add constraint songs_status_check
      check (status in ('active','removed'));
  end if;
end $$;

create index if not exists songs_status_idx on public.songs (status);

-- 5) VIDEOS
alter table public.videos
  add column if not exists owner_id uuid,
  add column if not exists owner_type text,
  add column if not exists video_url text,
  add column if not exists status text not null default 'active',
  add column if not exists views integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'videos_status_check'
  ) then
    alter table public.videos
      add constraint videos_status_check
      check (status in ('active','removed'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'videos_owner_type_check'
  ) then
    alter table public.videos
      add constraint videos_owner_type_check
      check (owner_type is null or owner_type in ('artist','dj'));
  end if;
end $$;

create index if not exists videos_status_idx on public.videos (status);
create index if not exists videos_owner_idx on public.videos (owner_type, owner_id);

-- 6) LIVE STREAMS
-- Already exists as control-plane table (status: live|ended). Keep as-is.

-- 7) FINANCE
-- We use an append-only ledger (transactions) + withdrawals; earnings are derived.
-- Provide a read-only view named `earnings` matching the requested schema shape.
create or replace view public.earnings as
with
  earned as (
    select
      target_id as user_id,
      target_type as role,
      coalesce(sum(coins), 0)::bigint as coins,
      coalesce(sum(amount_mwk), 0)::numeric(14,2) as amount_mwk
    from public.transactions
    where type in ('gift','battle_reward')
      and target_type in ('artist','dj')
      and target_id is not null
    group by target_id, target_type
  ),
  withdrawn as (
    select
      beneficiary_id as user_id,
      beneficiary_type as role,
      coalesce(sum(amount_mwk), 0)::numeric(14,2) as withdrawn
    from public.withdrawals
    where status in ('approved','paid')
    group by beneficiary_id, beneficiary_type
  )
select
  e.user_id,
  e.role,
  e.coins,
  e.amount_mwk,
  coalesce(w.withdrawn, 0)::numeric(14,2) as withdrawn
from earned e
left join withdrawn w
  on w.user_id = e.user_id and w.role = e.role;

-- 8) REPORTS + ADMIN LOGS: ensure required columns exist
alter table public.admin_logs
  add column if not exists reason text;

-- Optional: align reports minimal required fields (already created in moderation migration)
-- Keep status fields and deny-all RLS; app inserts via service role.
