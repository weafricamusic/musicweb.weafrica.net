-- Battle timeline (turn-based mic control)
--
-- Adds server-synced timeline state to `public.live_battles` so all clients can
-- compute the same current phase (Host A perform -> Host B perform -> Judging),
-- support pause/resume, and optionally allow manual phase switching.

alter table public.live_battles
  add column if not exists timeline_anchor_at timestamptz,
  add column if not exists timeline_anchor_elapsed_seconds integer not null default 0,
  add column if not exists timeline_paused_at timestamptz,
  add column if not exists timeline_perf_a_seconds integer not null default 480,
  add column if not exists timeline_perf_b_seconds integer not null default 480,
  add column if not exists timeline_judging_seconds integer not null default 240;

-- Basic safety constraints.
do $$
begin
  begin
    alter table public.live_battles
      add constraint live_battles_timeline_anchor_elapsed_non_negative
      check (timeline_anchor_elapsed_seconds >= 0);
  exception when duplicate_object then
    null;
  end;

  begin
    alter table public.live_battles
      add constraint live_battles_timeline_perf_a_non_negative
      check (timeline_perf_a_seconds >= 0);
  exception when duplicate_object then
    null;
  end;

  begin
    alter table public.live_battles
      add constraint live_battles_timeline_perf_b_non_negative
      check (timeline_perf_b_seconds >= 0);
  exception when duplicate_object then
    null;
  end;

  begin
    alter table public.live_battles
      add constraint live_battles_timeline_judging_non_negative
      check (timeline_judging_seconds >= 0);
  exception when duplicate_object then
    null;
  end;
end $$;

-- Backfill defaults for existing rows (defensive).
update public.live_battles
set
  timeline_anchor_elapsed_seconds = coalesce(timeline_anchor_elapsed_seconds, 0),
  timeline_perf_a_seconds = coalesce(timeline_perf_a_seconds, 480),
  timeline_perf_b_seconds = coalesce(timeline_perf_b_seconds, 480),
  timeline_judging_seconds = coalesce(timeline_judging_seconds, 240)
where
  timeline_anchor_elapsed_seconds is null
  or timeline_perf_a_seconds is null
  or timeline_perf_b_seconds is null
  or timeline_judging_seconds is null;
