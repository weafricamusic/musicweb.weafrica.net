-- Persistent stream session tracking for live room orchestration.
--
-- This repo persists live rooms in public.live_sessions, so stream_sessions
-- links to live_sessions.id rather than a non-existent live_rooms table.

create table if not exists public.stream_sessions (
  id text primary key,
  live_room_id uuid not null references public.live_sessions(id) on delete cascade,
  channel_id text not null,
  participants text[] not null default '{}'::text[],
  status text not null default 'CREATED' check (status in ('CREATED', 'ACTIVE', 'DISCONNECTED', 'CLOSED')),
  started_at timestamptz,
  ended_at timestamptz,
  viewer_count integer not null default 0,
  peak_viewers integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.stream_sessions
  add column if not exists live_room_id uuid,
  add column if not exists channel_id text,
  add column if not exists participants text[] not null default '{}'::text[],
  add column if not exists status text,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists viewer_count integer not null default 0,
  add column if not exists peak_viewers integer not null default 0,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.stream_sessions
set
  participants = coalesce(participants, '{}'::text[]),
  status = coalesce(nullif(trim(status), ''), 'CREATED'),
  viewer_count = coalesce(viewer_count, 0),
  peak_viewers = coalesce(peak_viewers, 0),
  metadata = coalesce(metadata, '{}'::jsonb),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  participants is null
  or status is null
  or trim(status) = ''
  or viewer_count is null
  or peak_viewers is null
  or metadata is null
  or created_at is null
  or updated_at is null;

do $$
begin
  begin
    alter table public.stream_sessions
      drop constraint if exists stream_sessions_status_check;
  exception
    when undefined_object then null;
  end;

  alter table public.stream_sessions
    add constraint stream_sessions_status_check
    check (status in ('CREATED', 'ACTIVE', 'DISCONNECTED', 'CLOSED'));
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_stream_sessions_live_room on public.stream_sessions(live_room_id);
create index if not exists idx_stream_sessions_status on public.stream_sessions(status);
create index if not exists idx_stream_sessions_channel on public.stream_sessions(channel_id);

drop trigger if exists trg_stream_sessions_touch on public.stream_sessions;
create trigger trg_stream_sessions_touch
before update on public.stream_sessions
for each row execute function public._touch_updated_at();

alter table public.stream_sessions enable row level security;
revoke all on table public.stream_sessions from anon, authenticated;