-- Followers table for artist follows (consumer -> artist).
-- Identity: Firebase UID stored as TEXT in followers.user_id.
-- Artist identity: artists.id is UUID.
-- This migration is idempotent and uses MVP allow-all RLS.

create extension if not exists pgcrypto;
create table if not exists public.followers (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artists(id) on delete cascade,
  user_id text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_followers_artist_user on public.followers (artist_id, user_id);
create index if not exists idx_followers_artist on public.followers (artist_id);
create index if not exists idx_followers_user on public.followers (user_id);
alter table public.followers enable row level security;
drop policy if exists followers_read_public on public.followers;
drop policy if exists followers_insert_self on public.followers;
drop policy if exists followers_delete_self on public.followers;

create policy followers_read_public
on public.followers
for select
to anon, authenticated
using (true);

create policy followers_insert_self
on public.followers
for insert
to authenticated
with check (auth.uid()::text = user_id);

create policy followers_delete_self
on public.followers
for delete
to authenticated
using (auth.uid()::text = user_id);
grant select on public.followers to anon, authenticated;
grant insert, delete on public.followers to authenticated;
notify pgrst, 'reload schema';
