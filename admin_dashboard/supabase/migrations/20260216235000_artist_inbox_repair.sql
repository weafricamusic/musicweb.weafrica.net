-- Repair + compatibility: artist inbox tables
--
-- Some environments report: "Messages are not configured in Supabase yet (missing artist_inbox tables)".
-- This migration is idempotent and safe across schema variants.
--
-- It creates/repairs:
-- - public.artist_inbox
-- - public.artist_inbox_messages
--
-- Design:
-- - RLS enabled + deny-all policies (safe default)
-- - anon/authenticated SELECT granted for PostgREST schema visibility (rows still blocked by RLS)
-- - service_role full access
--
-- Legacy safety:
-- - If public.artists does not exist yet, artist_inbox is created WITHOUT a foreign key.

create extension if not exists pgcrypto;

do $$
declare
  artists_exists boolean;
  inbox_exists boolean;
  messages_exists boolean;
begin
  select exists (
    select 1
    from information_schema.tables
    where table_schema='public' and table_name='artists'
  ) into artists_exists;

  select exists (
    select 1
    from information_schema.tables
    where table_schema='public' and table_name='artist_inbox'
  ) into inbox_exists;

  if not inbox_exists then
    if artists_exists then
      execute $sql$
        create table public.artist_inbox (
          id uuid primary key default gen_random_uuid(),
          artist_id uuid not null references public.artists(id) on delete cascade,
          title text,
          status text not null default 'open' check (status in ('open','closed','archived')),
          last_message_at timestamptz,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now(),
          meta jsonb not null default '{}'::jsonb
        )
      $sql$;
    else
      execute $sql$
        create table public.artist_inbox (
          id uuid primary key default gen_random_uuid(),
          artist_id uuid not null,
          title text,
          status text not null default 'open' check (status in ('open','closed','archived')),
          last_message_at timestamptz,
          created_at timestamptz not null default now(),
          updated_at timestamptz not null default now(),
          meta jsonb not null default '{}'::jsonb
        )
      $sql$;
    end if;
  end if;

  -- Ensure commonly expected columns exist.
  alter table if exists public.artist_inbox
    add column if not exists last_message_at timestamptz,
    add column if not exists meta jsonb;

  -- Indexes
  create index if not exists artist_inbox_artist_id_idx on public.artist_inbox (artist_id);
  create index if not exists artist_inbox_last_message_at_idx on public.artist_inbox (artist_id, last_message_at desc);

  -- Messages table
  select exists (
    select 1
    from information_schema.tables
    where table_schema='public' and table_name='artist_inbox_messages'
  ) into messages_exists;

  if not messages_exists then
    execute $sql$
      create table public.artist_inbox_messages (
        id uuid primary key default gen_random_uuid(),
        inbox_id uuid not null references public.artist_inbox(id) on delete cascade,
        sender_role text not null default 'system' check (sender_role in ('system','admin','artist')),
        sender_id text,
        body text not null,
        created_at timestamptz not null default now(),
        meta jsonb not null default '{}'::jsonb
      )
    $sql$;
  end if;

  -- If the table already existed, ensure expected columns exist.
  alter table if exists public.artist_inbox_messages
    add column if not exists sender_role text,
    add column if not exists sender_id text,
    add column if not exists body text,
    add column if not exists created_at timestamptz,
    add column if not exists meta jsonb;

  -- Best-effort defaults for legacy rows.
  update public.artist_inbox_messages set sender_role = coalesce(sender_role, 'system') where sender_role is null;
  update public.artist_inbox_messages set meta = coalesce(meta, '{}'::jsonb) where meta is null;
  update public.artist_inbox_messages set created_at = coalesce(created_at, now()) where created_at is null;

  -- Best-effort defaults (safe even if already set)
  alter table public.artist_inbox_messages alter column sender_role set default 'system';
  alter table public.artist_inbox_messages alter column meta set default '{}'::jsonb;
  alter table public.artist_inbox_messages alter column created_at set default now();

  -- Best-effort constraint (avoid failing if legacy data violates it).
  begin
    alter table public.artist_inbox_messages
      add constraint artist_inbox_messages_sender_role_check
      check (sender_role in ('system','admin','artist'));
  exception when duplicate_object then null;
  end;

  create index if not exists artist_inbox_messages_inbox_id_idx on public.artist_inbox_messages (inbox_id, created_at asc);

  -- RLS
  alter table public.artist_inbox enable row level security;
  alter table public.artist_inbox force row level security;

  alter table public.artist_inbox_messages enable row level security;
  alter table public.artist_inbox_messages force row level security;

  -- Deny-all policies
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

  -- PostgREST compatibility: make tables visible to anon/authenticated.
  grant usage on schema public to anon, authenticated;
  grant select on table public.artist_inbox to anon, authenticated;
  grant select on table public.artist_inbox_messages to anon, authenticated;

  -- Optional: allow service_role full access
  grant all on table public.artist_inbox to service_role;
  grant all on table public.artist_inbox_messages to service_role;

  notify pgrst, 'reload schema';
end $$;
