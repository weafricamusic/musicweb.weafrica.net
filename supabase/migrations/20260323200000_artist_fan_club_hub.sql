-- Artist Fan Club management tables.
-- Supports creator-side management for tiers, memberships, exclusive content,
-- announcements, and rewards from Studio.

create extension if not exists pgcrypto;

create table if not exists public.fan_club_tiers (
  id uuid primary key default gen_random_uuid(),
  artist_uid text not null,
  tier_key text not null check (tier_key in ('free', 'premium', 'vip')),
  title text not null,
  price_mwk integer not null default 0,
  description text,
  perks jsonb not null default '[]'::jsonb,
  badge_label text,
  accent_color text,
  is_active boolean not null default true,
  member_count_cache integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (artist_uid, tier_key)
);

create table if not exists public.fan_club_memberships (
  id uuid primary key default gen_random_uuid(),
  artist_uid text not null,
  fan_user_id text not null,
  tier_key text not null check (tier_key in ('free', 'premium', 'vip')),
  status text not null default 'active' check (status in ('active', 'paused', 'cancelled')),
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  total_spent_mwk numeric(14,2) not null default 0,
  gifts_sent_count integer not null default 0,
  comments_count integer not null default 0,
  notes text,
  unique (artist_uid, fan_user_id)
);

create table if not exists public.fan_club_content (
  id uuid primary key default gen_random_uuid(),
  artist_uid text not null,
  title text not null,
  description text,
  content_type text not null default 'message' check (content_type in ('song', 'video', 'message', 'image', 'audio')),
  access_tier text not null default 'premium' check (access_tier in ('free', 'premium', 'vip')),
  media_url text,
  plays_count integer not null default 0,
  comments_count integer not null default 0,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fan_club_announcements (
  id uuid primary key default gen_random_uuid(),
  artist_uid text not null,
  audience text not null check (audience in ('all', 'premium', 'vip', 'active_30d', 'custom')),
  message text not null,
  link_url text,
  image_url text,
  status text not null default 'sent' check (status in ('draft', 'sent')),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fan_club_rewards (
  id uuid primary key default gen_random_uuid(),
  artist_uid text not null,
  reward_type text not null check (reward_type in ('coins', 'exclusive_content', 'merch_discount', 'shoutout')),
  audience text not null check (audience in ('top_gifters', 'top_commenters', 'vip', 'custom')),
  note text,
  recipients jsonb not null default '[]'::jsonb,
  recipients_count integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists fan_club_tiers_artist_uid_idx
  on public.fan_club_tiers (artist_uid);

create index if not exists fan_club_memberships_artist_uid_idx
  on public.fan_club_memberships (artist_uid, tier_key, status);

create index if not exists fan_club_memberships_fan_uid_idx
  on public.fan_club_memberships (fan_user_id);

create index if not exists fan_club_content_artist_uid_idx
  on public.fan_club_content (artist_uid, published_at desc);

create index if not exists fan_club_announcements_artist_uid_idx
  on public.fan_club_announcements (artist_uid, created_at desc);

create index if not exists fan_club_rewards_artist_uid_idx
  on public.fan_club_rewards (artist_uid, created_at desc);

do $$
begin
  if exists (
    select 1
    from pg_proc
    where proname = 'tg_set_updated_at'
      and pg_function_is_visible(oid)
  ) then
    if not exists (select 1 from pg_trigger where tgname = 'fan_club_tiers_set_updated_at') then
      create trigger fan_club_tiers_set_updated_at
        before update on public.fan_club_tiers
        for each row
        execute function public.tg_set_updated_at();
    end if;

    if not exists (select 1 from pg_trigger where tgname = 'fan_club_memberships_set_updated_at') then
      create trigger fan_club_memberships_set_updated_at
        before update on public.fan_club_memberships
        for each row
        execute function public.tg_set_updated_at();
    end if;

    if not exists (select 1 from pg_trigger where tgname = 'fan_club_content_set_updated_at') then
      create trigger fan_club_content_set_updated_at
        before update on public.fan_club_content
        for each row
        execute function public.tg_set_updated_at();
    end if;

    if not exists (select 1 from pg_trigger where tgname = 'fan_club_announcements_set_updated_at') then
      create trigger fan_club_announcements_set_updated_at
        before update on public.fan_club_announcements
        for each row
        execute function public.tg_set_updated_at();
    end if;
  end if;
end $$;

create or replace function public.fan_club_refresh_tier_member_counts(p_artist_uid text)
returns void
language plpgsql
as $$
begin
  update public.fan_club_tiers t
     set member_count_cache = coalesce(src.member_count, 0),
         updated_at = now()
    from (
      select tier_key, count(*)::int as member_count
      from public.fan_club_memberships
      where artist_uid = p_artist_uid
        and status = 'active'
      group by tier_key
    ) src
   where t.artist_uid = p_artist_uid
     and t.tier_key = src.tier_key;

  update public.fan_club_tiers t
     set member_count_cache = 0,
         updated_at = now()
   where t.artist_uid = p_artist_uid
     and not exists (
       select 1
       from public.fan_club_memberships m
       where m.artist_uid = p_artist_uid
         and m.status = 'active'
         and m.tier_key = t.tier_key
     );
end;
$$;

create or replace function public.fan_club_memberships_sync_counts()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    perform public.fan_club_refresh_tier_member_counts(old.artist_uid);
    return old;
  end if;

  perform public.fan_club_refresh_tier_member_counts(new.artist_uid);

  if tg_op = 'UPDATE' and old.artist_uid <> new.artist_uid then
    perform public.fan_club_refresh_tier_member_counts(old.artist_uid);
  end if;

  return new;
end;
$$;

drop trigger if exists fan_club_memberships_sync_counts on public.fan_club_memberships;
create trigger fan_club_memberships_sync_counts
after insert or update or delete on public.fan_club_memberships
for each row
execute function public.fan_club_memberships_sync_counts();

alter table public.fan_club_tiers enable row level security;
alter table public.fan_club_memberships enable row level security;
alter table public.fan_club_content enable row level security;
alter table public.fan_club_announcements enable row level security;
alter table public.fan_club_rewards enable row level security;

alter table public.fan_club_tiers force row level security;
alter table public.fan_club_memberships force row level security;
alter table public.fan_club_content force row level security;
alter table public.fan_club_announcements force row level security;
alter table public.fan_club_rewards force row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'fan_club_tiers',
    'fan_club_memberships',
    'fan_club_content',
    'fan_club_announcements',
    'fan_club_rewards'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', 'owners_select_' || table_name, table_name);
    execute format('drop policy if exists %I on public.%I', 'owners_insert_' || table_name, table_name);
    execute format('drop policy if exists %I on public.%I', 'owners_update_' || table_name, table_name);
    execute format('drop policy if exists %I on public.%I', 'owners_delete_' || table_name, table_name);
  end loop;
end $$;

create policy owners_select_fan_club_tiers
  on public.fan_club_tiers
  for select to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_insert_fan_club_tiers
  on public.fan_club_tiers
  for insert to authenticated
  with check (artist_uid = auth.uid()::text);

create policy owners_update_fan_club_tiers
  on public.fan_club_tiers
  for update to authenticated
  using (artist_uid = auth.uid()::text)
  with check (artist_uid = auth.uid()::text);

create policy owners_delete_fan_club_tiers
  on public.fan_club_tiers
  for delete to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_select_fan_club_memberships
  on public.fan_club_memberships
  for select to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_insert_fan_club_memberships
  on public.fan_club_memberships
  for insert to authenticated
  with check (artist_uid = auth.uid()::text);

create policy owners_update_fan_club_memberships
  on public.fan_club_memberships
  for update to authenticated
  using (artist_uid = auth.uid()::text)
  with check (artist_uid = auth.uid()::text);

create policy owners_delete_fan_club_memberships
  on public.fan_club_memberships
  for delete to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_select_fan_club_content
  on public.fan_club_content
  for select to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_insert_fan_club_content
  on public.fan_club_content
  for insert to authenticated
  with check (artist_uid = auth.uid()::text);

create policy owners_update_fan_club_content
  on public.fan_club_content
  for update to authenticated
  using (artist_uid = auth.uid()::text)
  with check (artist_uid = auth.uid()::text);

create policy owners_delete_fan_club_content
  on public.fan_club_content
  for delete to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_select_fan_club_announcements
  on public.fan_club_announcements
  for select to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_insert_fan_club_announcements
  on public.fan_club_announcements
  for insert to authenticated
  with check (artist_uid = auth.uid()::text);

create policy owners_update_fan_club_announcements
  on public.fan_club_announcements
  for update to authenticated
  using (artist_uid = auth.uid()::text)
  with check (artist_uid = auth.uid()::text);

create policy owners_delete_fan_club_announcements
  on public.fan_club_announcements
  for delete to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_select_fan_club_rewards
  on public.fan_club_rewards
  for select to authenticated
  using (artist_uid = auth.uid()::text);

create policy owners_insert_fan_club_rewards
  on public.fan_club_rewards
  for insert to authenticated
  with check (artist_uid = auth.uid()::text);

create policy owners_update_fan_club_rewards
  on public.fan_club_rewards
  for update to authenticated
  using (artist_uid = auth.uid()::text)
  with check (artist_uid = auth.uid()::text);

create policy owners_delete_fan_club_rewards
  on public.fan_club_rewards
  for delete to authenticated
  using (artist_uid = auth.uid()::text);

notify pgrst, 'reload schema';