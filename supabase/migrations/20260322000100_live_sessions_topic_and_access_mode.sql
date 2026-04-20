-- Live sessions: store user-selected content topic + privacy/access mode
--
-- This is additive and safe to run multiple times.

alter table public.live_sessions
  add column if not exists topic text,
  add column if not exists access_mode text;

-- Optional: limit values, but keep best-effort (do not fail on legacy data).
do $$
begin
  begin
    alter table public.live_sessions
      add constraint live_sessions_access_mode_check
      check (access_mode in ('public','subscribers','private'));
  exception when duplicate_object then null;
  when others then null;
  end;
end $$;
