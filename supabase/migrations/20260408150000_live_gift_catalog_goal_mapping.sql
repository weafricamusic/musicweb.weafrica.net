-- Expand live gift catalog with explicit goal/scoring metadata.
-- This enables stable goal tracking and battle scoring per gift.

alter table if exists public.live_gifts
  add column if not exists category text,
  add column if not exists goal_bucket text,
  add column if not exists battle_points int,
  add column if not exists animation_url text;

alter table if exists public.live_gifts
  alter column category set default 'basic',
  alter column goal_bucket set default 'flowers',
  alter column battle_points set default 1;

-- Keep constraints additive and idempotent.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'live_gifts_goal_bucket_check'
      and conrelid = 'public.live_gifts'::regclass
  ) then
    alter table public.live_gifts
      add constraint live_gifts_goal_bucket_check
      check (goal_bucket in ('flowers', 'diamonds', 'drum'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'live_gifts_battle_points_check'
      and conrelid = 'public.live_gifts'::regclass
  ) then
    alter table public.live_gifts
      add constraint live_gifts_battle_points_check
      check (battle_points >= 0);
  end if;
end
$$;

-- Production gift catalog aligned to current Flutter gift model.
insert into public.live_gifts (id, name, coin_cost, icon_name, enabled, sort_order, category, goal_bucket, battle_points, animation_url)
values
  ('fire', 'Fire', 10, 'local_fire_department', true, 10, 'basic', 'flowers', 1, null),
  ('love', 'Love', 15, 'favorite', true, 20, 'basic', 'flowers', 1, null),
  ('mic', 'Mic', 30, 'mic', true, 30, 'music', 'drum', 3, null),
  ('diamond', 'Diamond', 60, 'diamond_outlined', true, 40, 'premium', 'diamonds', 10, null),
  ('crown', 'Crown', 90, 'workspace_premium', true, 50, 'premium', 'diamonds', 14, null),
  ('rocket', 'Rocket', 120, 'rocket_launch', true, 60, 'premium', 'drum', 20, null),
  ('rose', 'Rose', 25, 'local_florist', true, 70, 'african', 'flowers', 2, null),
  ('gift', 'Gift', 45, 'card_giftcard', true, 80, 'basic', 'flowers', 4, null),
  ('balloon', 'Balloon', 35, 'celebration_outlined', true, 90, 'african', 'flowers', 3, null),
  ('star', 'Star', 55, 'star', true, 100, 'music', 'drum', 6, null),
  ('fireworks', 'Fireworks', 100, 'celebration', true, 110, 'premium', 'diamonds', 12, null),
  ('rainbow', 'Rainbow', 140, 'auto_awesome', true, 120, 'premium', 'drum', 22, null)
on conflict (id) do update set
  name = excluded.name,
  coin_cost = excluded.coin_cost,
  icon_name = excluded.icon_name,
  enabled = excluded.enabled,
  sort_order = excluded.sort_order,
  category = excluded.category,
  goal_bucket = excluded.goal_bucket,
  battle_points = excluded.battle_points,
  animation_url = excluded.animation_url,
  updated_at = now();

create index if not exists live_gifts_goal_bucket_idx
  on public.live_gifts (goal_bucket)
  where enabled = true;

create or replace function public.live_goals_apply_gift_event()
returns trigger
language plpgsql
as $$
declare
  v_live_id text;
  v_host_id text;
  v_gift_key text;
  v_coins bigint;
  v_bucket text;
  v_flower_inc bigint := 0;
  v_diamond_inc bigint := 0;
  v_drum_inc bigint := 0;
begin
  v_live_id := coalesce(nullif(trim(new.live_id), ''), nullif(trim(new.stream_id::text), ''));
  v_host_id := coalesce(nullif(trim(new.to_host_id), ''), nullif(trim(new.to_uid), ''));
  v_gift_key := lower(coalesce(nullif(trim(new.gift_id), ''), nullif(trim(new.gift_type), ''), ''));
  v_coins := greatest(coalesce(new.coin_cost, new.coins, 0), 0);

  if v_live_id is null or v_host_id is null or v_coins <= 0 then
    return new;
  end if;

  select g.goal_bucket
    into v_bucket
    from public.live_gifts g
    where g.id = v_gift_key
    limit 1;

  if v_bucket is null then
    if v_gift_key like '%diamond%' then
      v_bucket := 'diamonds';
    elsif v_gift_key like '%mic%' or v_gift_key like '%drum%' then
      v_bucket := 'drum';
    else
      v_bucket := 'flowers';
    end if;
  end if;

  if v_bucket = 'diamonds' then
    v_diamond_inc := v_coins;
  elsif v_bucket = 'drum' then
    v_drum_inc := v_coins;
  else
    v_flower_inc := v_coins;
  end if;

  insert into public.live_goals (
    live_id,
    host_id,
    flower_current,
    diamond_current,
    drum_current,
    updated_at
  ) values (
    v_live_id,
    v_host_id,
    v_flower_inc,
    v_diamond_inc,
    v_drum_inc,
    now()
  )
  on conflict (live_id, host_id)
  do update set
    flower_current = public.live_goals.flower_current + excluded.flower_current,
    diamond_current = public.live_goals.diamond_current + excluded.diamond_current,
    drum_current = public.live_goals.drum_current + excluded.drum_current,
    updated_at = now();

  return new;
end;
$$;
