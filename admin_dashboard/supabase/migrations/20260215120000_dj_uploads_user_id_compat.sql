-- Compatibility: legacy clients expect public.dj_mixes.user_id and public.dj_uploads
--
-- Observed errors:
-- - column dj_mixes.user_id does not exist
-- - Could not find the table 'public.dj_uploads' in the schema cache
--
-- This migration is idempotent and safe to apply on existing projects.

create extension if not exists pgcrypto;

-- 1) Add legacy column to dj_mixes
alter table public.dj_mixes
  add column if not exists user_id text;

-- Legacy clients also expect a "type" column on dj_uploads.
-- Keep it nullable but default to 'mix' to preserve basic semantics.
alter table public.dj_mixes
  add column if not exists type text default 'mix';

update public.dj_mixes set type = 'mix' where type is null;

create index if not exists dj_mixes_user_id_idx on public.dj_mixes (user_id);

create index if not exists dj_mixes_type_idx on public.dj_mixes (type);

-- Best-effort backfill from dj_users mapping table when possible.
update public.dj_mixes m
set user_id = u.user_id
from public.dj_users u
where m.user_id is null
  and u.user_id is not null
  and length(trim(u.user_id)) > 0
  and m.dj_id is not null
  and length(trim(m.dj_id)) > 0
  and u.dj_id = m.dj_id;

-- 2) Legacy table name: expose dj_uploads as a view over dj_mixes.
-- We add INSTEAD OF triggers so older clients can still insert/update/delete.
create or replace view public.dj_uploads as
select
  id,
  dj_id,
  user_id,
  title,
  description,
  audio_url,
  audio_path,
  cover_url,
  cover_path,
  duration_seconds,
  is_active,
  created_at,
  updated_at,
  type
from public.dj_mixes;

-- Write-through triggers
create or replace function public.dj_uploads_ins() returns trigger
language plpgsql
as $$
begin
  insert into public.dj_mixes (
    id,
    dj_id,
    user_id,
    type,
    title,
    description,
    audio_url,
    audio_path,
    cover_url,
    cover_path,
    duration_seconds,
    is_active,
    created_at,
    updated_at
  ) values (
    coalesce(new.id, gen_random_uuid()),
    new.dj_id,
    new.user_id,
    coalesce(new.type, 'mix'),
    new.title,
    new.description,
    new.audio_url,
    new.audio_path,
    new.cover_url,
    new.cover_path,
    new.duration_seconds,
    coalesce(new.is_active, true),
    coalesce(new.created_at, now()),
    coalesce(new.updated_at, now())
  )
  returning * into new;

  return new;
end;
$$;

create or replace function public.dj_uploads_upd() returns trigger
language plpgsql
as $$
begin
  update public.dj_mixes
  set
    dj_id = new.dj_id,
    user_id = new.user_id,
    type = coalesce(new.type, old.type, 'mix'),
    title = new.title,
    description = new.description,
    audio_url = new.audio_url,
    audio_path = new.audio_path,
    cover_url = new.cover_url,
    cover_path = new.cover_path,
    duration_seconds = new.duration_seconds,
    is_active = new.is_active,
    created_at = new.created_at,
    updated_at = coalesce(new.updated_at, now())
  where id = old.id
  returning * into new;

  return new;
end;
$$;

create or replace function public.dj_uploads_del() returns trigger
language plpgsql
as $$
begin
  delete from public.dj_mixes where id = old.id;
  return old;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'dj_uploads_ins_trigger'
  ) then
    create trigger dj_uploads_ins_trigger
    instead of insert on public.dj_uploads
    for each row execute function public.dj_uploads_ins();
  end if;

  if not exists (
    select 1 from pg_trigger where tgname = 'dj_uploads_upd_trigger'
  ) then
    create trigger dj_uploads_upd_trigger
    instead of update on public.dj_uploads
    for each row execute function public.dj_uploads_upd();
  end if;

  if not exists (
    select 1 from pg_trigger where tgname = 'dj_uploads_del_trigger'
  ) then
    create trigger dj_uploads_del_trigger
    instead of delete on public.dj_uploads
    for each row execute function public.dj_uploads_del();
  end if;
end $$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
