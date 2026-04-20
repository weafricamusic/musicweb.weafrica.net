-- STEP 8 — Battle setup metadata (title/category/schedule/monetization/rules)
--
-- Adds lightweight columns to live_battles so the app can:
-- - render premium LIVE NOW + UPCOMING battle cards
-- - persist battle setup details created by hosts
--
-- Backwards-compatible: all columns are nullable / have safe defaults.

-- 1) live_battles columns
alter table public.live_battles
  add column if not exists title text,
  add column if not exists category text,
  add column if not exists duration_seconds integer,
  add column if not exists scheduled_at timestamptz,
  add column if not exists access_mode text,
  add column if not exists price_coins integer,
  add column if not exists gift_enabled boolean,
  add column if not exists voting_enabled boolean,
  add column if not exists battle_format text,
  add column if not exists round_count integer;

-- 2) Backfill defaults where null
update public.live_battles
set
  duration_seconds = coalesce(duration_seconds, 30 * 60),
  access_mode = coalesce(nullif(trim(access_mode), ''), 'free'),
  gift_enabled = coalesce(gift_enabled, true),
  voting_enabled = coalesce(voting_enabled, false),
  battle_format = coalesce(nullif(trim(battle_format), ''), 'continuous'),
  round_count = coalesce(round_count, 3)
where
  duration_seconds is null
  or access_mode is null
  or gift_enabled is null
  or voting_enabled is null
  or battle_format is null
  or round_count is null;

-- 3) Constraints (best-effort; do not fail if already present)
do $$
begin
  -- access_mode
  begin
    alter table public.live_battles
      add constraint live_battles_access_mode_check
      check (access_mode in ('free','subscribers','ticket'));
  exception when duplicate_object then
    null;
  end;

  -- battle_format
  begin
    alter table public.live_battles
      add constraint live_battles_format_check
      check (battle_format in ('continuous','rounds'));
  exception when duplicate_object then
    null;
  end;
end $$;

-- 4) Indexes for Upcoming battles
create index if not exists live_battles_scheduled_at_idx
  on public.live_battles (scheduled_at desc)
  where scheduled_at is not null;
