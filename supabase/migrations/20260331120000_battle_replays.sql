-- Battle replays (minimal v1)
--
-- Notes:
-- - This stores replay metadata (URL + state) for a battle.
-- - Recording provider integration (e.g., Agora Cloud Recording) can be layered on later.
-- - No public RLS policies are added; Edge Functions use service role.

create extension if not exists pgcrypto;

-- Ensure the shared updated_at trigger helper exists.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.battle_replays') is not null then
    return;
  end if;

  create table public.battle_replays (
    id bigserial primary key,

    battle_id text not null references public.live_battles(battle_id) on delete cascade,
    channel_id text,

    provider text not null default 'manual',
    status text not null default 'recording' check (status in ('recording','processing','ready','failed')),

    replay_url text,
    error_message text,

    started_by_uid text,
    started_at timestamptz not null default now(),
    stopped_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );

  alter table public.battle_replays enable row level security;
end $$;

create unique index if not exists battle_replays_battle_id_uniq
  on public.battle_replays (battle_id);

create index if not exists battle_replays_status_idx
  on public.battle_replays (status);

create index if not exists battle_replays_started_at_idx
  on public.battle_replays (started_at desc);

do $$
begin
  if to_regclass('public.battle_replays') is null then
    return;
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgname = 'battle_replays_set_updated_at'
  ) then
    create trigger battle_replays_set_updated_at
      before update on public.battle_replays
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;
