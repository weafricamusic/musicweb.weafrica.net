-- Repair legacy battle_invites foreign key drift.
--
-- Some environments still have battle_invites.battle_id pointing at
-- public.battles(id), which blocks the Nest orchestrator because it creates
-- rows in public.live_battles(battle_id).

do $$
declare
  fk_name text;
begin
  if to_regclass('public.battle_invites') is null then
    return;
  end if;

  if to_regclass('public.live_battles') is null then
    return;
  end if;

  begin
    alter table public.battle_invites
      alter column battle_id type text using battle_id::text;
  exception
    when undefined_column then
      return;
  end;

  for fk_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace rel_ns on rel_ns.oid = rel.relnamespace
    join pg_class ref on ref.oid = con.confrelid
    join pg_namespace ref_ns on ref_ns.oid = ref.relnamespace
    where con.contype = 'f'
      and rel_ns.nspname = 'public'
      and rel.relname = 'battle_invites'
      and ref_ns.nspname = 'public'
      and ref.relname <> 'live_battles'
  loop
    execute format(
      'alter table public.battle_invites drop constraint if exists %I',
      fk_name
    );
  end loop;

  if not exists (
    select 1
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace rel_ns on rel_ns.oid = rel.relnamespace
    join pg_class ref on ref.oid = con.confrelid
    join pg_namespace ref_ns on ref_ns.oid = ref.relnamespace
    where con.contype = 'f'
      and rel_ns.nspname = 'public'
      and rel.relname = 'battle_invites'
      and ref_ns.nspname = 'public'
      and ref.relname = 'live_battles'
  ) then
    alter table public.battle_invites
      add constraint battle_invites_battle_id_fkey
      foreign key (battle_id)
      references public.live_battles(battle_id)
      on delete cascade;
  end if;
end $$;