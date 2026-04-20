-- LIVE MODERATION: reports
-- Minimal anonymous report logging for live chat safety.

create table if not exists public.live_reports (
  id uuid primary key default gen_random_uuid(),
  live_id uuid references public.live_sessions(id) on delete set null,
  reporter_user_id text,
  reported_user_id text,
  reason text not null default 'unspecified',
  message text,
  created_at timestamptz not null default now()
);

create index if not exists live_reports_created_at_idx
  on public.live_reports (created_at desc);
create index if not exists live_reports_live_id_idx
  on public.live_reports (live_id, created_at desc);

alter table public.live_reports enable row level security;

-- Anyone can insert reports.
do $$
begin
  create policy "Public insert live reports" on public.live_reports
    for insert
    to anon, authenticated
    with check (true);
exception
  when duplicate_object then null;
end $$;

-- No public reads.
do $$
begin
  create policy "Deny read live reports" on public.live_reports
    for select
    to anon, authenticated
    using (false);
exception
  when duplicate_object then null;
end $$;

grant insert on table public.live_reports to anon, authenticated;
