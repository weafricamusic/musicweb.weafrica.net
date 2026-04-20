-- Feed builder + engagement analytics tables.
--
-- These tables are backend-owned. Clients read feed data through the Nest API.

create extension if not exists pgcrypto;

create table if not exists public.feed_items (
  id uuid primary key default gen_random_uuid(),
  item_type text not null check (item_type in ('live', 'battle', 'song', 'video', 'event')),
  item_id text not null,
  creator_id text,
  title text,
  thumbnail_url text,
  score numeric not null default 0,
  view_count integer not null default 0,
  like_count integer not null default 0,
  comment_count integer not null default 0,
  gift_count integer not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.feed_items
  add column if not exists item_type text,
  add column if not exists item_id text,
  add column if not exists creator_id text,
  add column if not exists title text,
  add column if not exists thumbnail_url text,
  add column if not exists score numeric,
  add column if not exists view_count integer,
  add column if not exists like_count integer,
  add column if not exists comment_count integer,
  add column if not exists gift_count integer,
  add column if not exists created_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists metadata jsonb,
  add column if not exists updated_at timestamptz;

update public.feed_items
set
  score = coalesce(score, 0),
  view_count = coalesce(view_count, 0),
  like_count = coalesce(like_count, 0),
  comment_count = coalesce(comment_count, 0),
  gift_count = coalesce(gift_count, 0),
  metadata = coalesce(metadata, '{}'::jsonb),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  score is null
  or view_count is null
  or like_count is null
  or comment_count is null
  or gift_count is null
  or metadata is null
  or created_at is null
  or updated_at is null;

create table if not exists public.user_feed (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  feed_item_id uuid not null references public.feed_items(id) on delete cascade,
  seen boolean not null default false,
  engaged boolean not null default false,
  engagement_type text,
  seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_feed
  add column if not exists user_id text,
  add column if not exists feed_item_id uuid,
  add column if not exists seen boolean,
  add column if not exists engaged boolean,
  add column if not exists engagement_type text,
  add column if not exists seen_at timestamptz,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

update public.user_feed
set
  seen = coalesce(seen, false),
  engaged = coalesce(engaged, false),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  seen is null
  or engaged is null
  or created_at is null
  or updated_at is null;

create table if not exists public.engagement_events (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  target_type text not null check (target_type in ('live', 'battle', 'song', 'video', 'artist', 'event')),
  target_id text not null,
  event_type text not null check (event_type in ('view', 'like', 'comment', 'gift', 'share', 'follow')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.engagement_events
  add column if not exists user_id text,
  add column if not exists target_type text,
  add column if not exists target_id text,
  add column if not exists event_type text,
  add column if not exists metadata jsonb,
  add column if not exists created_at timestamptz;

update public.engagement_events
set
  metadata = coalesce(metadata, '{}'::jsonb),
  created_at = coalesce(created_at, now())
where
  metadata is null
  or created_at is null;

do $$
begin
  begin
    alter table public.feed_items
      drop constraint if exists feed_items_item_type_check;
  exception
    when undefined_object then null;
  end;

  alter table public.feed_items
    add constraint feed_items_item_type_check
    check (item_type in ('live', 'battle', 'song', 'video', 'event'));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  begin
    alter table public.engagement_events
      drop constraint if exists engagement_events_target_type_check;
  exception
    when undefined_object then null;
  end;

  alter table public.engagement_events
    add constraint engagement_events_target_type_check
    check (target_type in ('live', 'battle', 'song', 'video', 'artist', 'event'));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  begin
    alter table public.engagement_events
      drop constraint if exists engagement_events_event_type_check;
  exception
    when undefined_object then null;
  end;

  alter table public.engagement_events
    add constraint engagement_events_event_type_check
    check (event_type in ('view', 'like', 'comment', 'gift', 'share', 'follow'));
exception
  when duplicate_object then null;
end $$;

create unique index if not exists feed_items_type_item_unique
  on public.feed_items (item_type, item_id);

create unique index if not exists user_feed_user_item_unique
  on public.user_feed (user_id, feed_item_id);

create index if not exists idx_feed_items_score
  on public.feed_items (score desc, created_at desc);

create index if not exists idx_feed_items_type
  on public.feed_items (item_type, created_at desc);

create index if not exists idx_feed_items_expires_at
  on public.feed_items (expires_at);

create index if not exists idx_user_feed_user
  on public.user_feed (user_id, created_at desc);

create index if not exists idx_user_feed_seen
  on public.user_feed (user_id, seen, engaged, created_at desc);

create index if not exists idx_engagement_target
  on public.engagement_events (target_type, target_id, created_at desc);

create index if not exists idx_engagement_user
  on public.engagement_events (user_id, created_at desc);

drop trigger if exists trg_feed_items_touch on public.feed_items;
create trigger trg_feed_items_touch
before update on public.feed_items
for each row execute function public._touch_updated_at();

drop trigger if exists trg_user_feed_touch on public.user_feed;
create trigger trg_user_feed_touch
before update on public.user_feed
for each row execute function public._touch_updated_at();

alter table public.feed_items enable row level security;
alter table public.user_feed enable row level security;
alter table public.engagement_events enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'feed_items'
      and policyname = 'deny_all_feed_items'
  ) then
    create policy deny_all_feed_items
      on public.feed_items
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_feed'
      and policyname = 'deny_all_user_feed'
  ) then
    create policy deny_all_user_feed
      on public.user_feed
      for all
      using (false)
      with check (false);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'engagement_events'
      and policyname = 'deny_all_engagement_events'
  ) then
    create policy deny_all_engagement_events
      on public.engagement_events
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.feed_items from anon, authenticated;
revoke all on table public.user_feed from anon, authenticated;
revoke all on table public.engagement_events from anon, authenticated;

notify pgrst, 'reload schema';