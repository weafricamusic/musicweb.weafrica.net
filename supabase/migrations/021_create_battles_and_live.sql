-- Create battles + related tables for Live & Battle features.
-- Identity: Firebase UID stored as TEXT (dj_id/user_id).
-- This migration is idempotent and uses MVP allow-all RLS policies/grants.

create extension if not exists pgcrypto;
-- 1) Battles
create table if not exists public.battles (
  id uuid primary key default gen_random_uuid(),
  dj_id text not null,
  title text not null default 'Battle',
  status text not null default 'scheduled',
  type text not null default 'battle',
  is_live boolean not null default false,
  starts_at timestamptz not null default now(),
  duration_minutes integer not null default 20,
  started_at timestamptz,
  ended_at timestamptz,
  viewers integer not null default 0,
  prize_pool integer not null default 0,
  winner_id text,
  participant_ids text[] not null default '{}'::text[],
  participants jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_battles_dj_id on public.battles (dj_id);
create index if not exists idx_battles_is_live on public.battles (is_live);
create index if not exists idx_battles_starts_at on public.battles (starts_at);
-- 2) Votes (one per user per battle)
create table if not exists public.battle_votes (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_battle_votes_battle_user on public.battle_votes (battle_id, user_id);
create index if not exists idx_battle_votes_battle on public.battle_votes (battle_id);
-- 3) Reminders (one per user per battle)
create table if not exists public.battle_reminders (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_battle_reminders_battle_user on public.battle_reminders (battle_id, user_id);
create index if not exists idx_battle_reminders_battle on public.battle_reminders (battle_id);
-- 4) Presence (optional; enables tracking live participants/viewers)
create table if not exists public.battle_presence (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id text not null,
  role text not null default 'viewer',
  joined_at timestamptz not null default now(),
  left_at timestamptz
);
create index if not exists idx_battle_presence_battle on public.battle_presence (battle_id);
create index if not exists idx_battle_presence_user on public.battle_presence (user_id);
-- 4b) Comments (includes system join messages)
create table if not exists public.battle_comments (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id text,
  message text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_battle_comments_battle on public.battle_comments (battle_id);
create index if not exists idx_battle_comments_created_at on public.battle_comments (created_at);
-- 4c) Likes (one per user per battle)
create table if not exists public.battle_likes (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_battle_likes_battle_user on public.battle_likes (battle_id, user_id);
create index if not exists idx_battle_likes_battle on public.battle_likes (battle_id);
-- 4d) Shares
create table if not exists public.battle_shares (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  user_id text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_battle_shares_battle on public.battle_shares (battle_id);
-- 4e) Gifts (coin tips). MVP: recorded only; wallet debit/credit handled elsewhere.
create table if not exists public.battle_gifts (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  from_user_id text not null,
  coins numeric not null default 0,
  message text,
  created_at timestamptz not null default now()
);
create index if not exists idx_battle_gifts_battle on public.battle_gifts (battle_id);
-- 4f) System message on join
create or replace function public.fn_battle_presence_join_message()
returns trigger
language plpgsql
as $$
begin
  insert into public.battle_comments (battle_id, user_id, message, is_system, created_at)
  values (new.battle_id, new.user_id, coalesce(new.user_id, 'Someone') || ' joined', true, now());
  return new;
end;
$$;
drop trigger if exists trg_battle_presence_join_message on public.battle_presence;
create trigger trg_battle_presence_join_message
after insert on public.battle_presence
for each row
execute function public.fn_battle_presence_join_message();
-- 5) MVP RLS policies + grants
alter table public.battles enable row level security;
alter table public.battle_votes enable row level security;
alter table public.battle_reminders enable row level security;
alter table public.battle_presence enable row level security;
alter table public.battle_comments enable row level security;
alter table public.battle_likes enable row level security;
alter table public.battle_shares enable row level security;
alter table public.battle_gifts enable row level security;
do $$
declare
  r record;
begin
  -- Drop policies (idempotent refresh)
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'battles',
        'battle_votes',
        'battle_reminders',
        'battle_presence',
        'battle_comments',
        'battle_likes',
        'battle_shares',
        'battle_gifts'
      )
  ) loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  execute 'create policy mvp_public_all on public.battles for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_votes for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_reminders for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_presence for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_comments for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_likes for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_shares for all using (true) with check (true)';
  execute 'create policy mvp_public_all on public.battle_gifts for all using (true) with check (true)';
end $$;
grant select, insert, update, delete on public.battles to anon, authenticated;
grant select, insert, update, delete on public.battle_votes to anon, authenticated;
grant select, insert, update, delete on public.battle_reminders to anon, authenticated;
grant select, insert, update, delete on public.battle_presence to anon, authenticated;
grant select, insert, update, delete on public.battle_comments to anon, authenticated;
grant select, insert, update, delete on public.battle_likes to anon, authenticated;
grant select, insert, update, delete on public.battle_shares to anon, authenticated;
grant select, insert, update, delete on public.battle_gifts to anon, authenticated;
-- Ask PostgREST to reload schema cache.
notify pgrst, 'reload schema';
