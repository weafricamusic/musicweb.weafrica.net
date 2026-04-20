-- Minimal artist inbox tables (PostgREST-visible, RLS-deny by default)
--
-- Some clients probe for inbox/message tables via the REST schema cache using anon/authenticated keys.
-- If privileges are fully revoked, PostgREST will behave as if the table does not exist (PGRST205).
--
-- This migration:
-- - Creates public.artist_inbox and public.artist_inbox_messages if missing.
-- - Enables + forces RLS and adds deny-all policies (safe default).
-- - Grants anon/authenticated SELECT for schema visibility (rows still blocked by RLS).
-- - Grants service_role full access.

-- 1) Base tables
create table if not exists public.artist_inbox (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artists(id) on delete cascade,
  title text,
  status text not null default 'open' check (status in ('open','closed','archived')),
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);

-- If the table already existed from an older/manual setup, ensure expected columns exist.
alter table public.artist_inbox add column if not exists last_message_at timestamptz;

create index if not exists artist_inbox_artist_id_idx on public.artist_inbox (artist_id);
create index if not exists artist_inbox_last_message_at_idx on public.artist_inbox (artist_id, last_message_at desc);

create table if not exists public.artist_inbox_messages (
  id uuid primary key default gen_random_uuid(),
  inbox_id uuid not null references public.artist_inbox(id) on delete cascade,
  sender_role text not null default 'system' check (sender_role in ('system','admin','artist')),
  sender_id text,
  body text not null,
  created_at timestamptz not null default now(),
  meta jsonb not null default '{}'::jsonb
);

create index if not exists artist_inbox_messages_inbox_id_idx on public.artist_inbox_messages (inbox_id, created_at asc);

-- 2) RLS + deny-all policies (safe default; add real policies later)
alter table public.artist_inbox enable row level security;
alter table public.artist_inbox force row level security;

alter table public.artist_inbox_messages enable row level security;
alter table public.artist_inbox_messages force row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'artist_inbox'
      and policyname = 'deny_all_artist_inbox'
  ) then
    create policy deny_all_artist_inbox
      on public.artist_inbox
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'artist_inbox_messages'
      and policyname = 'deny_all_artist_inbox_messages'
  ) then
    create policy deny_all_artist_inbox_messages
      on public.artist_inbox_messages
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- 3) PostgREST compatibility: make tables visible to anon/authenticated.
-- With RLS enabled + deny-all policies, SELECT returns zero rows.
grant usage on schema public to anon, authenticated;
grant select on table public.artist_inbox to anon, authenticated;
grant select on table public.artist_inbox_messages to anon, authenticated;

-- Optional: allow service_role full access
grant all on table public.artist_inbox to service_role;
grant all on table public.artist_inbox_messages to service_role;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
