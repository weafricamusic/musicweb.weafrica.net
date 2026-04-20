-- Song streams event log (used for fake-stream detection)
-- Note: This app uses Firebase Auth, so user_id is TEXT (firebase uid).

create extension if not exists pgcrypto;

create table if not exists public.song_streams (
  id uuid primary key default gen_random_uuid(),
  user_id text,
  song_id uuid,
  duration_seconds int,
  device_id text,
  created_at timestamptz not null default now()
);

create index if not exists song_streams_created_at_idx on public.song_streams (created_at desc);
create index if not exists song_streams_user_created_at_idx on public.song_streams (user_id, created_at desc);
create index if not exists song_streams_song_created_at_idx on public.song_streams (song_id, created_at desc);
create index if not exists song_streams_user_song_created_at_idx on public.song_streams (user_id, song_id, created_at desc);

alter table public.song_streams enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'song_streams'
      and policyname = 'deny_all_song_streams'
  ) then
    create policy deny_all_song_streams
      on public.song_streams
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.song_streams from anon, authenticated;
grant select, insert, update on table public.song_streams to service_role;
