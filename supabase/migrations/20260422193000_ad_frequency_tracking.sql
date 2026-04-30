-- Ad frequency tracking for free users with 3-2-5 pattern
--
-- This migration adds tables and functions to track ad frequency for free users
-- following the pattern: ad after 3 songs, then after 2 songs, then after 5 songs, repeat

-- Table to track user ad frequency state
create table if not exists public.user_ad_frequency (
  id uuid not null default gen_random_uuid (),
  user_id text not null,
  current_pattern_index integer not null default 0, -- 0=3, 1=2, 2=5
  songs_since_last_ad integer not null default 0,
  total_ads_shown integer not null default 0,
  last_ad_shown_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_ad_frequency_pkey primary key (id),
  constraint user_ad_frequency_user_id_unique unique (user_id)
) TABLESPACE pg_default;

-- Index for efficient lookups
create index if not exists user_ad_frequency_user_id_idx on public.user_ad_frequency (user_id);

-- Function to get or create user ad frequency state
create or replace function public.get_or_create_user_ad_frequency(p_user_id text)
returns public.user_ad_frequency
language plpgsql
security definer
as $$
declare
  result public.user_ad_frequency;
begin
  -- Try to get existing record
  select * into result from public.user_ad_frequency where user_id = p_user_id;
  
  -- If not found, create new record
  if not found then
    insert into public.user_ad_frequency (user_id)
    values (p_user_id)
    returning * into result;
  end if;
  
  return result;
end;
$$;

-- Function to check if ad should be shown for a user
create or replace function public.should_show_ad_for_user(p_user_id text)
returns boolean
language plpgsql
security definer
as $$
declare
  user_state public.user_ad_frequency;
  current_threshold integer;
begin
  -- Get or create user state
  user_state := public.get_or_create_user_ad_frequency(p_user_id);
  
  -- Determine current threshold based on pattern index
  -- Pattern: 0=3 songs, 1=2 songs, 2=5 songs
  case user_state.current_pattern_index
    when 0 then current_threshold := 3;
    when 1 then current_threshold := 2;
    when 2 then current_threshold := 5;
    else current_threshold := 3; -- fallback
  end case;
  
  -- Check if we've reached the threshold
  return user_state.songs_since_last_ad >= current_threshold;
end;
$$;

-- Function to increment song play count for a user
create or replace function public.increment_song_play_count(p_user_id text)
returns public.user_ad_frequency
language plpgsql
security definer
as $$
declare
  user_state public.user_ad_frequency;
begin
  -- Get or create user state
  user_state := public.get_or_create_user_ad_frequency(p_user_id);
  
  -- Increment song count
  update public.user_ad_frequency
  set songs_since_last_ad = songs_since_last_ad + 1,
      updated_at = now()
  where user_id = p_user_id
  returning * into user_state;
  
  return user_state;
end;
$$;

-- Function to reset ad frequency state after showing an ad
create or replace function public.reset_ad_frequency_after_ad(p_user_id text)
returns public.user_ad_frequency
language plpgsql
security definer
as $$
declare
  user_state public.user_ad_frequency;
begin
  -- Get or create user state
  user_state := public.get_or_create_user_ad_frequency(p_user_id);
  
  -- Reset song count and increment ad count
  update public.user_ad_frequency
  set songs_since_last_ad = 0,
      total_ads_shown = total_ads_shown + 1,
      last_ad_shown_at = now(),
      current_pattern_index = (current_pattern_index + 1) % 3, -- Move to next pattern
      updated_at = now()
  where user_id = p_user_id
  returning * into user_state;
  
  return user_state;
end;
$$;

-- Function to get user ad frequency stats
create or replace function public.get_user_ad_frequency_stats(p_user_id text)
returns table (
  songs_since_last_ad integer,
  current_pattern_index integer,
  current_pattern_songs_needed integer,
  total_ads_shown integer,
  last_ad_shown_at timestamptz
)
language plpgsql
security definer
as $$
declare
  user_state public.user_ad_frequency;
  current_threshold integer;
begin
  -- Get or create user state
  user_state := public.get_or_create_user_ad_frequency(p_user_id);
  
  -- Determine current threshold
  case user_state.current_pattern_index
    when 0 then current_threshold := 3;
    when 1 then current_threshold := 2;
    when 2 then current_threshold := 5;
    else current_threshold := 3; -- fallback
  end case;
  
  return query select
    user_state.songs_since_last_ad,
    user_state.current_pattern_index,
    current_threshold,
    user_state.total_ads_shown,
    user_state.last_ad_shown_at;
end;
$$;

-- Enable RLS on the table
alter table public.user_ad_frequency enable row level security;

-- RLS policies - only allow service role to modify
create policy "user_ad_frequency_service_role_only" on public.user_ad_frequency
for all using (auth.role() = 'service_role');

-- Grant permissions to service role
grant all on public.user_ad_frequency to service_role;
grant usage on schema public to service_role;
grant execute on function public.get_or_create_user_ad_frequency(text) to service_role;
grant execute on function public.should_show_ad_for_user(text) to service_role;
grant execute on function public.increment_song_play_count(text) to service_role;
grant execute on function public.reset_ad_frequency_after_ad(text) to service_role;
grant execute on function public.get_user_ad_frequency_stats(text) to service_role;