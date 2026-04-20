-- Add beat_id to public.events for live/battle metadata.
--
-- The Flutter app stores BeatModel.id as a String, so beat_id is stored as TEXT.
-- Idempotent and safe to apply on environments where events already exists.

do $$
begin
  if to_regclass('public.events') is not null then
    execute 'alter table public.events add column if not exists beat_id text';
  end if;
end
$$;
