-- Compatibility patch: live_sessions artist_uid/artist_id/host_id
--
-- Some environments/table versions use a legacy required column `artist_uid` (TEXT, sometimes NOT NULL),
-- while the current Edge API writes `host_id` + `artist_id` and does not set `artist_uid`.
--
-- Symptom:
--   Failed to mark live: null value in column "artist_uid" of relation "live_sessions" violates not-null constraint
--
-- This migration:
-- - Ensures `host_id`, `artist_id`, and `artist_uid` columns exist
-- - Backfills missing values from whichever column is populated
-- - Installs a trigger to keep them in sync for inserts/updates
--
-- Result: starting a live session (artist or DJ) no longer fails due to schema drift.

alter table public.live_sessions
  add column if not exists host_id text,
  add column if not exists artist_id text,
  add column if not exists artist_uid text;

-- Best-effort backfill for existing rows.
update public.live_sessions
set host_id = coalesce(
  nullif(btrim(host_id), ''),
  nullif(btrim(artist_id), ''),
  nullif(btrim(artist_uid), '')
)
where host_id is null
   or length(btrim(host_id)) = 0;

update public.live_sessions
set artist_id = coalesce(
  nullif(btrim(artist_id), ''),
  nullif(btrim(host_id), ''),
  nullif(btrim(artist_uid), '')
)
where artist_id is null
   or length(btrim(artist_id)) = 0;

update public.live_sessions
set artist_uid = coalesce(
  nullif(btrim(artist_uid), ''),
  nullif(btrim(host_id), ''),
  nullif(btrim(artist_id), '')
)
where artist_uid is null
   or length(btrim(artist_uid)) = 0;

create or replace function public._live_sessions_coalesce_creator_uids()
returns trigger
language plpgsql
as $$
begin
  -- If newer columns are set but legacy column is missing, copy over.
  if (new.artist_uid is null or length(btrim(new.artist_uid)) = 0) then
    if new.host_id is not null and length(btrim(new.host_id)) > 0 then
      new.artist_uid := new.host_id;
    elsif new.artist_id is not null and length(btrim(new.artist_id)) > 0 then
      new.artist_uid := new.artist_id;
    end if;
  end if;

  -- If legacy column is set but newer columns are missing, copy over.
  if (new.host_id is null or length(btrim(new.host_id)) = 0)
    and new.artist_uid is not null
    and length(btrim(new.artist_uid)) > 0
  then
    new.host_id := new.artist_uid;
  end if;

  if (new.artist_id is null or length(btrim(new.artist_id)) = 0)
    and new.artist_uid is not null
    and length(btrim(new.artist_uid)) > 0
  then
    new.artist_id := new.artist_uid;
  end if;

  -- Keep host_id and artist_id aligned (artist_id is treated as an alias).
  if (new.artist_id is null or length(btrim(new.artist_id)) = 0)
    and new.host_id is not null
    and length(btrim(new.host_id)) > 0
  then
    new.artist_id := new.host_id;
  end if;

  if (new.host_id is null or length(btrim(new.host_id)) = 0)
    and new.artist_id is not null
    and length(btrim(new.artist_id)) > 0
  then
    new.host_id := new.artist_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_live_sessions_coalesce_creator_uids on public.live_sessions;

create trigger trg_live_sessions_coalesce_creator_uids
before insert or update of host_id, artist_id, artist_uid
on public.live_sessions
for each row
execute function public._live_sessions_coalesce_creator_uids();
