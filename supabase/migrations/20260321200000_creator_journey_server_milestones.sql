-- Server-side creator journey milestones.
--
-- Purpose:
-- - fire milestone pushes immediately from canonical DB writes
-- - keep client-side milestone detection as a fallback, not the only source
--
-- Covered server-side sources in this migration:
-- - artist followers via public.followers
-- - DJ followers via public.dj_profile.followers_count
-- - artist earnings via public.artist_wallets.earned_coins
-- - artist plays via public.songs.streams
-- - DJ plays/earnings via public.dj_sets.plays / public.dj_sets.coins_earned

create extension if not exists pgcrypto;

create table if not exists public.creator_journey_milestone_progress (
  user_uid text not null,
  metric text not null,
  threshold bigint not null,
  current_value bigint not null default 0,
  source text,
  reached_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_uid, metric, threshold)
);

create index if not exists creator_journey_milestone_progress_metric_idx
  on public.creator_journey_milestone_progress (metric, updated_at desc);

alter table public.creator_journey_milestone_progress enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'creator_journey_milestone_progress'
      and policyname = 'deny_all_creator_journey_milestone_progress'
  ) then
    create policy deny_all_creator_journey_milestone_progress
      on public.creator_journey_milestone_progress
      for all
      using (false)
      with check (false);
  end if;
end $$;

create or replace function public.creator_journey_metric_thresholds(p_metric text)
returns bigint[]
language sql
immutable
as $$
  select case lower(coalesce(p_metric, ''))
    when 'plays' then array[100::bigint, 1000::bigint]
    when 'followers' then array[10::bigint, 50::bigint]
    when 'earnings' then array[1000::bigint, 2500::bigint]
    else array[]::bigint[]
  end;
$$;

create or replace function public.creator_journey_template_for_metric(p_metric text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(p_metric, ''))
    when 'plays' then 'milestone_plays'
    when 'followers' then 'milestone_followers'
    when 'earnings' then 'milestone_earnings'
    else ''
  end;
$$;

create or replace function public.creator_journey_handle_milestone(
  p_user_uid text,
  p_role text,
  p_metric text,
  p_current_value bigint,
  p_source text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_uid text := nullif(trim(coalesce(p_user_uid, '')), '');
  v_role text := nullif(trim(coalesce(p_role, '')), '');
  v_metric text := lower(trim(coalesce(p_metric, '')));
  v_current bigint := greatest(coalesce(p_current_value, 0), 0);
  v_threshold bigint;
  v_template_key text;
  v_event_key text;
  v_inserted_threshold bigint;
begin
  if v_user_uid is null or v_metric = '' or v_current <= 0 then
    return;
  end if;

  v_template_key := public.creator_journey_template_for_metric(v_metric);
  if v_template_key = '' then
    return;
  end if;

  insert into public.creator_journey_state (
    user_uid,
    role,
    last_event_at,
    created_at,
    updated_at
  ) values (
    v_user_uid,
    v_role,
    now(),
    now(),
    now()
  )
  on conflict (user_uid) do update
    set role = coalesce(excluded.role, public.creator_journey_state.role),
        last_event_at = greatest(coalesce(public.creator_journey_state.last_event_at, excluded.last_event_at), excluded.last_event_at),
        updated_at = now();

  foreach v_threshold in array public.creator_journey_metric_thresholds(v_metric)
  loop
    continue when v_current < v_threshold;

    v_inserted_threshold := null;
    insert into public.creator_journey_milestone_progress (
      user_uid,
      metric,
      threshold,
      current_value,
      source,
      reached_at,
      created_at,
      updated_at
    ) values (
      v_user_uid,
      v_metric,
      v_threshold,
      v_current,
      p_source,
      now(),
      now(),
      now()
    )
    on conflict (user_uid, metric, threshold) do nothing
    returning threshold into v_inserted_threshold;

    update public.creator_journey_milestone_progress
      set current_value = greatest(current_value, v_current),
          source = coalesce(p_source, source),
          updated_at = now()
      where user_uid = v_user_uid
        and metric = v_metric
        and threshold = v_threshold;

    continue when v_inserted_threshold is null;

    v_event_key := coalesce(v_role, 'creator') || ':' || v_metric || ':' || v_threshold::text;

    insert into public.creator_journey_events (
      user_uid,
      event_type,
      event_key,
      occurred_at,
      metadata,
      created_at
    ) values (
      v_user_uid,
      'milestone_reached',
      v_event_key,
      now(),
      jsonb_build_object(
        'role', v_role,
        'metric', v_metric,
        'threshold', v_threshold,
        'current_value', v_current,
        'source', p_source,
        'origin', 'server'
      ),
      now()
    )
    on conflict (user_uid, event_type, event_key) do nothing;

    insert into public.creator_journey_push_queue (
      user_uid,
      template_key,
      dedupe_key,
      send_at,
      status,
      payload,
      created_at,
      updated_at
    ) values (
      v_user_uid,
      v_template_key,
      'v1:' || v_template_key || ':' || v_event_key,
      now() + interval '1 minute',
      'pending',
      jsonb_build_object(
        'metric', v_metric,
        'threshold', v_threshold,
        'current_value', v_current,
        'role', v_role,
        'source', p_source,
        'origin', 'server'
      ),
      now(),
      now()
    )
    on conflict (user_uid, dedupe_key) do nothing;
  end loop;
end;
$$;

revoke all on function public.creator_journey_handle_milestone(text, text, text, bigint, text) from public;
grant execute on function public.creator_journey_handle_milestone(text, text, text, bigint, text) to service_role;

create or replace function public.creator_journey_after_artist_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_artist_id uuid := new.artist_id;
  v_user_uid text;
  v_total bigint;
begin
  select a.user_id
    into v_user_uid
    from public.artists a
   where a.id = v_artist_id
   limit 1;

  if v_user_uid is null or trim(v_user_uid) = '' then
    return new;
  end if;

  select count(*)::bigint
    into v_total
    from public.followers f
   where f.artist_id = v_artist_id;

  perform public.creator_journey_handle_milestone(v_user_uid, 'artist', 'followers', coalesce(v_total, 0), 'followers');
  return new;
end;
$$;

drop trigger if exists trg_creator_journey_after_artist_follow on public.followers;
create trigger trg_creator_journey_after_artist_follow
after insert on public.followers
for each row
execute function public.creator_journey_after_artist_follow();

create or replace function public.creator_journey_after_dj_profile_milestones()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and coalesce(new.followers_count, 0) <= coalesce(old.followers_count, 0) then
    return new;
  end if;

  perform public.creator_journey_handle_milestone(new.dj_uid, 'dj', 'followers', coalesce(new.followers_count, 0), 'dj_profile');
  return new;
end;
$$;

drop trigger if exists trg_creator_journey_after_dj_profile_milestones on public.dj_profile;
create trigger trg_creator_journey_after_dj_profile_milestones
after insert or update of followers_count on public.dj_profile
for each row
execute function public.creator_journey_after_dj_profile_milestones();

create or replace function public.creator_journey_after_artist_wallet_milestones()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and coalesce(new.earned_coins, 0) <= coalesce(old.earned_coins, 0) then
    return new;
  end if;

  perform public.creator_journey_handle_milestone(new.artist_id, 'artist', 'earnings', coalesce(new.earned_coins, 0), 'artist_wallets');
  return new;
end;
$$;

drop trigger if exists trg_creator_journey_after_artist_wallet_milestones on public.artist_wallets;
create trigger trg_creator_journey_after_artist_wallet_milestones
after insert or update of earned_coins on public.artist_wallets
for each row
execute function public.creator_journey_after_artist_wallet_milestones();

create or replace function public.creator_journey_after_song_streams()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_uid text := nullif(trim(coalesce(new.user_id, new.artist, '')), '');
  v_artist_id uuid := new.artist_id;
  v_total bigint;
begin
  if tg_op = 'UPDATE' and coalesce(new.streams, 0) <= coalesce(old.streams, 0) then
    return new;
  end if;

  if v_user_uid is null and v_artist_id is not null then
    select a.user_id
      into v_user_uid
      from public.artists a
     where a.id = v_artist_id
     limit 1;
  end if;

  if v_user_uid is null or trim(v_user_uid) = '' then
    return new;
  end if;

  select coalesce(sum(greatest(coalesce(s.streams, 0), 0)), 0)::bigint
    into v_total
    from public.songs s
   where s.user_id = v_user_uid
      or (v_artist_id is not null and s.artist_id = v_artist_id);

  perform public.creator_journey_handle_milestone(v_user_uid, 'artist', 'plays', coalesce(v_total, 0), 'songs');
  return new;
end;
$$;

drop trigger if exists trg_creator_journey_after_song_streams on public.songs;
create trigger trg_creator_journey_after_song_streams
after insert or update of streams on public.songs
for each row
execute function public.creator_journey_after_song_streams();

create or replace function public.creator_journey_after_dj_set_milestones()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_plays bigint;
  v_total_earnings bigint;
begin
  if tg_op = 'INSERT' then
    if coalesce(new.plays, 0) > 0 then
      select coalesce(sum(greatest(coalesce(s.plays, 0), 0)), 0)::bigint
        into v_total_plays
        from public.dj_sets s
       where s.dj_uid = new.dj_uid;

      perform public.creator_journey_handle_milestone(new.dj_uid, 'dj', 'plays', coalesce(v_total_plays, 0), 'dj_sets');
    end if;

    if coalesce(new.coins_earned, 0) > 0 then
      select coalesce(sum(greatest(coalesce(s.coins_earned, 0), 0)), 0)::bigint
        into v_total_earnings
        from public.dj_sets s
       where s.dj_uid = new.dj_uid;

      perform public.creator_journey_handle_milestone(new.dj_uid, 'dj', 'earnings', coalesce(v_total_earnings, 0), 'dj_sets');
    end if;

    return new;
  end if;

  if coalesce(new.plays, 0) > coalesce(old.plays, 0) then
    select coalesce(sum(greatest(coalesce(s.plays, 0), 0)), 0)::bigint
      into v_total_plays
      from public.dj_sets s
     where s.dj_uid = new.dj_uid;

    perform public.creator_journey_handle_milestone(new.dj_uid, 'dj', 'plays', coalesce(v_total_plays, 0), 'dj_sets');
  end if;

  if coalesce(new.coins_earned, 0) > coalesce(old.coins_earned, 0) then
    select coalesce(sum(greatest(coalesce(s.coins_earned, 0), 0)), 0)::bigint
      into v_total_earnings
      from public.dj_sets s
     where s.dj_uid = new.dj_uid;

    perform public.creator_journey_handle_milestone(new.dj_uid, 'dj', 'earnings', coalesce(v_total_earnings, 0), 'dj_sets');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_creator_journey_after_dj_set_milestones on public.dj_sets;
create trigger trg_creator_journey_after_dj_set_milestones
after insert or update of plays, coins_earned on public.dj_sets
for each row
execute function public.creator_journey_after_dj_set_milestones();

notify pgrst, 'reload schema';