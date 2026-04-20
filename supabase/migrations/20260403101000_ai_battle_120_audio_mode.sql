-- Add battle-specific metadata for AI beat audio jobs (120s fairness mode)
-- and seed pricing for the new action.

alter table if exists public.ai_beat_audio_jobs
  add column if not exists mode text,
  add column if not exists battle_id text,
  add column if not exists fairness_template_id text,
  add column if not exists fairness_lock jsonb;

create index if not exists ai_beat_audio_jobs_mode_created_at_idx
  on public.ai_beat_audio_jobs (mode, created_at desc);

create index if not exists ai_beat_audio_jobs_battle_id_idx
  on public.ai_beat_audio_jobs (battle_id);

insert into public.ai_pricing (action, coin_cost, daily_free_limit, enabled, updated_at)
values ('beat_audio_battle_120', 250, 1, true, now())
on conflict (action) do update
  set coin_cost = excluded.coin_cost,
      daily_free_limit = excluded.daily_free_limit,
      enabled = excluded.enabled,
      updated_at = now();
