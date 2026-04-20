-- Compatibility patch: battle_invites from_artist_uid/to_artist_uid
--
-- Some environments/table versions use `from_artist_uid` and `to_artist_uid` (TEXT, often NOT NULL),
-- while existing invite writers (RPC/Edge) may only set `from_uid` / `to_uid`.
--
-- This migration:
-- - Adds the artist UID columns if missing (nullable by default)
-- - Backfills them from legacy columns (best-effort)
-- - Installs a trigger to keep both pairs in sync for inserts/updates

alter table public.battle_invites add column if not exists from_artist_uid text;
alter table public.battle_invites add column if not exists to_artist_uid text;

-- Best-effort backfill for existing rows.
update public.battle_invites
  set from_artist_uid = from_uid
where (from_artist_uid is null or length(trim(from_artist_uid)) = 0)
  and from_uid is not null
  and length(trim(from_uid)) > 0;

update public.battle_invites
  set to_artist_uid = to_uid
where (to_artist_uid is null or length(trim(to_artist_uid)) = 0)
  and to_uid is not null
  and length(trim(to_uid)) > 0;

create or replace function public._battle_invites_coalesce_artist_uids()
returns trigger
language plpgsql
as $$
begin
  -- If newer columns are set but legacy columns are missing, copy over.
  if (new.from_uid is null or length(trim(new.from_uid)) = 0)
    and new.from_artist_uid is not null
    and length(trim(new.from_artist_uid)) > 0
  then
    new.from_uid := new.from_artist_uid;
  end if;

  if (new.to_uid is null or length(trim(new.to_uid)) = 0)
    and new.to_artist_uid is not null
    and length(trim(new.to_artist_uid)) > 0
  then
    new.to_uid := new.to_artist_uid;
  end if;

  -- If legacy columns are set but newer columns are missing, copy over.
  if (new.from_artist_uid is null or length(trim(new.from_artist_uid)) = 0)
    and new.from_uid is not null
    and length(trim(new.from_uid)) > 0
  then
    new.from_artist_uid := new.from_uid;
  end if;

  if (new.to_artist_uid is null or length(trim(new.to_artist_uid)) = 0)
    and new.to_uid is not null
    and length(trim(new.to_uid)) > 0
  then
    new.to_artist_uid := new.to_uid;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_battle_invites_coalesce_artist_uids on public.battle_invites;

create trigger trg_battle_invites_coalesce_artist_uids
before insert or update of from_uid, to_uid, from_artist_uid, to_artist_uid
on public.battle_invites
for each row
execute function public._battle_invites_coalesce_artist_uids();
