-- Keep live goals in sync with gift events at the database layer.
-- Additive and backward-compatible across legacy live_gift_events column variants.

alter table if exists public.live_gift_events
  add column if not exists live_id text,
  add column if not exists to_host_id text,
  add column if not exists gift_id text,
  add column if not exists coin_cost bigint;

create or replace function public.live_goals_apply_gift_event()
returns trigger
language plpgsql
as $$
declare
  v_live_id text;
  v_host_id text;
  v_gift_key text;
  v_coins bigint;
  v_flower_inc bigint := 0;
  v_diamond_inc bigint := 0;
  v_drum_inc bigint := 0;
begin
  v_live_id := coalesce(nullif(trim(new.live_id), ''), nullif(trim(new.stream_id::text), ''));
  v_host_id := coalesce(nullif(trim(new.to_host_id), ''), nullif(trim(new.to_uid), ''));
  v_gift_key := lower(coalesce(nullif(trim(new.gift_type), ''), nullif(trim(new.gift_id), ''), ''));
  v_coins := greatest(coalesce(new.coin_cost, new.coins, 0), 0);

  if v_live_id is null or v_host_id is null or v_coins <= 0 then
    return new;
  end if;

  if v_gift_key like '%diamond%' then
    v_diamond_inc := v_coins;
  elsif v_gift_key like '%mic%' or v_gift_key like '%drum%' then
    v_drum_inc := v_coins;
  elsif v_gift_key like '%rose%' or v_gift_key like '%flower%' then
    v_flower_inc := v_coins;
  else
    -- Default bucket for uncategorized gifts.
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

drop trigger if exists trg_live_goals_apply_gift_event on public.live_gift_events;
create trigger trg_live_goals_apply_gift_event
after insert on public.live_gift_events
for each row
execute function public.live_goals_apply_gift_event();
