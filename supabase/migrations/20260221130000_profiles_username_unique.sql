-- Enforce unique usernames for professional search/invites UX.
-- Note: uses a partial unique index so existing null/empty usernames don't break.

-- Backfill/cleanup: if historical data contains duplicate usernames, the unique
-- index below will fail to create. Keep the first row per username and clear the
-- rest so users can pick a new unique username later.
do $$
begin
  with ranked as (
    select
      id,
      row_number() over (
        partition by lower(btrim(username))
        order by updated_at nulls last, created_at nulls last, id
      ) as rn
    from public.profiles
    where username is not null and btrim(username) <> ''
  )
  update public.profiles p
    set username = null
  from ranked r
  where p.id = r.id
    and r.rn > 1;
exception
  when undefined_column then
    -- If the table is older and lacks updated_at/created_at, skip cleanup.
    null;
end $$;

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username))
  where username is not null and btrim(username) <> '';
