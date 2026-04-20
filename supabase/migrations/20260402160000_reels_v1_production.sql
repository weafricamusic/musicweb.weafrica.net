-- ============================================
-- MIGRATION: reels_v1_production
-- ============================================

-- 1) Core tables
create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  user_id text references public.profiles(id) on delete cascade not null,
  video_url text not null,
  thumbnail_url text,
  caption text,
  music_title text,
  music_artist text,
  duration int check (duration > 0),
  likes_count int default 0 check (likes_count >= 0),
  comments_count int default 0 check (comments_count >= 0),
  shares_count int default 0 check (shares_count >= 0),
  views_count int default 0 check (views_count >= 0),
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.reel_likes (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid references public.reels(id) on delete cascade not null,
  user_id text references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now(),
  unique (reel_id, user_id)
);

create table if not exists public.reel_comments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid references public.reels(id) on delete cascade not null,
  user_id text references public.profiles(id) on delete cascade not null,
  parent_id uuid references public.reel_comments(id) on delete set null,
  content text not null check (char_length(content) <= 500),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.reel_impressions (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid references public.reels(id) on delete cascade,
  user_id text references public.profiles(id) on delete set null,
  session_id text,
  watch_duration int check (watch_duration >= 0),
  completed boolean default false,
  created_at timestamptz default now()
);

-- 2) Counter triggers
create or replace function public.update_reel_likes_count()
returns trigger
set search_path = public
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.reels
    set likes_count = likes_count + 1,
        updated_at = now()
    where id = new.reel_id;
  elsif tg_op = 'DELETE' then
    update public.reels
    set likes_count = greatest(likes_count - 1, 0),
        updated_at = now()
    where id = old.reel_id;
  end if;

  return null;
end;
$$;

create or replace function public.update_reel_comments_count()
returns trigger
set search_path = public
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    update public.reels
    set comments_count = comments_count + 1,
        updated_at = now()
    where id = new.reel_id;
  elsif tg_op = 'DELETE' then
    update public.reels
    set comments_count = greatest(comments_count - 1, 0),
        updated_at = now()
    where id = old.reel_id;
  end if;

  return null;
end;
$$;

create or replace function public.update_updated_at_column()
returns trigger
set search_path = public
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists reel_likes_trigger on public.reel_likes;
create trigger reel_likes_trigger
after insert or delete on public.reel_likes
for each row execute function public.update_reel_likes_count();

drop trigger if exists reel_comments_trigger on public.reel_comments;
create trigger reel_comments_trigger
after insert or delete on public.reel_comments
for each row execute function public.update_reel_comments_count();

drop trigger if exists update_reels_updated_at on public.reels;
create trigger update_reels_updated_at
before update on public.reels
for each row execute function public.update_updated_at_column();

-- 3) Secure idempotent RPC
create or replace function public.toggle_reel_like(p_reel_id uuid)
returns jsonb
set search_path = public
security definer
language plpgsql
as $$
declare
  v_user_id text;
  v_liked boolean;
  v_likes_count int;
begin
  v_user_id := auth.uid()::text;
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select exists (
    select 1 from public.reel_likes
    where reel_id = p_reel_id
      and user_id = v_user_id
  )
  into v_liked;

  if v_liked then
    delete from public.reel_likes
    where reel_id = p_reel_id
      and user_id = v_user_id;

    select likes_count into v_likes_count
    from public.reels
    where id = p_reel_id;

    return jsonb_build_object('liked', false, 'likes_count', coalesce(v_likes_count, 0));
  end if;

  insert into public.reel_likes (reel_id, user_id)
  values (p_reel_id, v_user_id)
  on conflict (reel_id, user_id) do nothing;

  select likes_count into v_likes_count
  from public.reels
  where id = p_reel_id;

  return jsonb_build_object('liked', true, 'likes_count', coalesce(v_likes_count, 0));
end;
$$;

revoke all on function public.toggle_reel_like(uuid) from public;
grant execute on function public.toggle_reel_like(uuid) to authenticated;
grant execute on function public.toggle_reel_like(uuid) to service_role;

-- 4) Indexes
create index if not exists idx_reels_feed
  on public.reels(is_active, created_at desc, id desc);

create index if not exists idx_reel_comments_lookup
  on public.reel_comments(reel_id, created_at);

create index if not exists idx_reel_likes_lookup
  on public.reel_likes(reel_id, user_id);

create index if not exists idx_reel_impressions_reel
  on public.reel_impressions(reel_id);

-- 5) RLS
alter table public.reels enable row level security;
alter table public.reel_likes enable row level security;
alter table public.reel_comments enable row level security;
alter table public.reel_impressions enable row level security;

drop policy if exists "Anyone can view active reels" on public.reels;
create policy "Anyone can view active reels"
on public.reels
for select
using (is_active = true);

drop policy if exists "Artists can update their own reels" on public.reels;
create policy "Artists can update their own reels"
on public.reels
for update
using (auth.uid()::text = user_id);

drop policy if exists "Artists can delete their own reels" on public.reels;
create policy "Artists can delete their own reels"
on public.reels
for delete
using (auth.uid()::text = user_id);

drop policy if exists "Artists can insert their own reels" on public.reels;
create policy "Artists can insert their own reels"
on public.reels
for insert
with check (auth.uid()::text = user_id);

drop policy if exists "Anyone can view likes" on public.reel_likes;
create policy "Anyone can view likes"
on public.reel_likes
for select
using (true);

drop policy if exists "Users can like via own uid" on public.reel_likes;
create policy "Users can like via own uid"
on public.reel_likes
for all
using (auth.uid()::text = user_id)
with check (auth.uid()::text = user_id);

drop policy if exists "Anyone can view comments" on public.reel_comments;
create policy "Anyone can view comments"
on public.reel_comments
for select
using (true);

drop policy if exists "Users can insert flat comments" on public.reel_comments;
create policy "Users can insert flat comments"
on public.reel_comments
for insert
with check (auth.uid()::text = user_id and parent_id is null);

drop policy if exists "Users can update their own comments" on public.reel_comments;
create policy "Users can update their own comments"
on public.reel_comments
for update
using (auth.uid()::text = user_id);

drop policy if exists "Users can delete their own comments" on public.reel_comments;
create policy "Users can delete their own comments"
on public.reel_comments
for delete
using (auth.uid()::text = user_id);

drop policy if exists "Anyone can insert impressions" on public.reel_impressions;
create policy "Anyone can insert impressions"
on public.reel_impressions
for insert
with check (true);

-- 6) Realtime publication (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'reels'
  ) then
    alter publication supabase_realtime add table public.reels;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'reel_likes'
  ) then
    alter publication supabase_realtime add table public.reel_likes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'reel_comments'
  ) then
    alter publication supabase_realtime add table public.reel_comments;
  end if;
end;
$$;

-- 7) Optional public storage bucket for V1 playback
insert into storage.buckets (id, name, public)
values ('reels', 'reels', true)
on conflict (id) do nothing;
