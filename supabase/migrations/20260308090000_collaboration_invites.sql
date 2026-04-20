-- Creator collaborations (DJ/Artist)
--
-- Minimal backend to support the DJ Dashboard "Collaborations" screen.
-- NOTE: Uses MVP allow-all RLS policies (aligns with other dashboard tables).

create extension if not exists pgcrypto;

create table if not exists public.collaboration_invites (
  id uuid primary key default gen_random_uuid(),

  from_uid text not null,
  from_role text,
  to_uid text not null,
  to_role text,

  message text,
  status text not null default 'pending' check (status in (
    'pending',
    'accepted',
    'declined',
    'cancelled'
  )),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists collaboration_invites_to_uid_created_at_idx
  on public.collaboration_invites (to_uid, created_at desc);
create index if not exists collaboration_invites_from_uid_created_at_idx
  on public.collaboration_invites (from_uid, created_at desc);
create index if not exists collaboration_invites_status_created_at_idx
  on public.collaboration_invites (status, created_at desc);

alter table public.collaboration_invites enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'collaboration_invites'
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy mvp_public_all on public.collaboration_invites for all using (true) with check (true)';
end $$;

grant select, insert, update, delete on table public.collaboration_invites to anon, authenticated;

-- Ask PostgREST to reload schema cache.
notify pgrst, 'reload schema';
