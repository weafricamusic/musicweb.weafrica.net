-- Enforce creator_profiles.user_id integrity for reliable upserts.
-- Applies only when public.creator_profiles is a real table.

do $$
declare
  rel_kind "char";
begin
  select c.relkind
    into rel_kind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'creator_profiles';

  if rel_kind = 'r' then
    delete from public.creator_profiles
    where user_id is null;

    alter table public.creator_profiles
      alter column user_id set not null;

    if not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.creator_profiles'::regclass
        and contype = 'u'
        and pg_get_constraintdef(oid) = 'UNIQUE (user_id)'
    ) then
      alter table public.creator_profiles
        add constraint creator_profiles_user_id_key unique (user_id);
    end if;
  else
    raise notice 'public.creator_profiles is not a table (relkind=%). Skipping integrity migration.', coalesce(rel_kind::text, 'missing');
  end if;
end $$;

notify pgrst, 'reload schema';
