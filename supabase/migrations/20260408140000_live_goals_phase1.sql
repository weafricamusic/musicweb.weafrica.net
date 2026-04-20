-- Phase 1 live goals table for solo live goal tracking.
-- Additive migration: no renames or destructive changes.

create table if not exists public.live_goals (
  id uuid primary key default gen_random_uuid(),
  live_id text not null,
  host_id text not null,
  flower_target bigint not null default 20000 check (flower_target >= 0),
  flower_current bigint not null default 0 check (flower_current >= 0),
  diamond_target bigint not null default 5000 check (diamond_target >= 0),
  diamond_current bigint not null default 0 check (diamond_current >= 0),
  drum_target bigint not null default 1000 check (drum_target >= 0),
  drum_current bigint not null default 0 check (drum_current >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (live_id, host_id)
);

create index if not exists live_goals_live_id_idx
  on public.live_goals (live_id);

create index if not exists live_goals_host_id_idx
  on public.live_goals (host_id);

alter table public.live_goals enable row level security;

-- Public read for live viewers.
drop policy if exists "live_goals_select_authenticated" on public.live_goals;
create policy "live_goals_select_authenticated"
  on public.live_goals
  for select
  to authenticated
  using (true);

-- Hosts can insert goals for their own lives.
drop policy if exists "live_goals_insert_owner" on public.live_goals;
create policy "live_goals_insert_owner"
  on public.live_goals
  for insert
  to authenticated
  with check (
    host_id = auth.uid()::text
  );

-- Hosts can update goals for their own lives.
drop policy if exists "live_goals_update_owner" on public.live_goals;
create policy "live_goals_update_owner"
  on public.live_goals
  for update
  to authenticated
  using (
    host_id = auth.uid()::text
  )
  with check (
    host_id = auth.uid()::text
  );

-- Hosts can delete their own goals if live is ended or reset.
drop policy if exists "live_goals_delete_owner" on public.live_goals;
create policy "live_goals_delete_owner"
  on public.live_goals
  for delete
  to authenticated
  using (
    host_id = auth.uid()::text
  );
