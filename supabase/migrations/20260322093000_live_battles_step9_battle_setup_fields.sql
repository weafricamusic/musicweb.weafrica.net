-- STEP 9 — Battle setup fields (battle_type/beat/coin_goal/country)
--
-- Extends live_battles to store the required battle configuration selected
-- by the host in PreLive Studio.
--
-- Backwards-compatible: all columns are nullable.

alter table public.live_battles
  add column if not exists battle_type text,
  add column if not exists beat_name text,
  add column if not exists coin_goal integer,
  add column if not exists country text;

-- Best-effort constraints.
do $$
begin
  begin
    alter table public.live_battles
      add constraint live_battles_coin_goal_non_negative
      check (coin_goal is null or coin_goal >= 0);
  exception when duplicate_object then
    null;
  end;
end $$;
