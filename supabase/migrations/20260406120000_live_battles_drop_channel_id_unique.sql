-- Allow multiple live battles per channel_id.
-- Historically channel_id was declared UNIQUE (constraint like live_battles_channel_id_key).

-- Drop any UNIQUE constraint whose definition is exactly UNIQUE (channel_id).
do $$
declare
  r record;
begin
  -- If the table doesn't exist yet (fresh project ordering issues), just no-op.
  if to_regclass('public.live_battles') is null then
    return;
  end if;

  for r in (
    select
      c.conname as conname,
      pg_get_constraintdef(c.oid) as condef
    from pg_constraint c
    where c.conrelid = 'public.live_battles'::regclass
      and c.contype = 'u'
  ) loop
    if r.condef ilike 'unique (%channel_id%)'
      and r.condef not ilike 'unique (%channel_id%,%'
    then
      execute format('alter table public.live_battles drop constraint if exists %I', r.conname);
    end if;
  end loop;
end $$;

-- If a standalone unique index was created (rare), drop it too.
-- (Dropping the constraint above usually removes the backing index automatically.)
drop index if exists public.live_battles_channel_id_key;
