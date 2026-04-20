-- Adds a simple live type discriminator to keep Live independent from Events/Tickets.
-- live_type meanings:
-- - normal: free, real-time live session
-- - premium: subscriber/followers-gated (future)
-- - event: ticket-gated (future)

alter table if exists public.live_sessions
  add column if not exists live_type text not null default 'normal';

-- Add a safe check constraint (idempotent).
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'live_sessions_live_type_check'
  ) then
    alter table public.live_sessions
      add constraint live_sessions_live_type_check
      check (live_type in ('normal', 'premium', 'event'));
  end if;
end
$$;

create index if not exists live_sessions_live_type_idx
  on public.live_sessions (live_type);
