-- STEP 2.1 (follow-up) — Persist Agora UIDs for battle hosts
-- This lets clients reliably render the two broadcasters even when many audience members join.

alter table public.live_battles
  add column if not exists host_a_agora_uid bigint,
  add column if not exists host_b_agora_uid bigint;
-- Replace claim function with an Agora UID-aware version.
drop function if exists public.battle_claim_host(text, text, text);
create or replace function public.battle_claim_host(
  p_battle_id text,
  p_channel_id text,
  p_user_id text,
  p_agora_uid bigint
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
  b public.live_battles;
  au bigint := nullif(p_agora_uid, 0);
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_channel_id is null or length(trim(p_channel_id)) = 0 then
    raise exception 'channel_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;

  insert into public.live_battles(battle_id, channel_id)
  values (trim(p_battle_id), trim(p_channel_id))
  on conflict (battle_id) do nothing;

  select * into b
  from public.live_battles
  where battle_id = trim(p_battle_id)
  for update;

  if b.host_a_id = trim(p_user_id) then
    update public.live_battles
      set host_a_agora_uid = coalesce(au, host_a_agora_uid)
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  if b.host_b_id = trim(p_user_id) then
    update public.live_battles
      set host_b_agora_uid = coalesce(au, host_b_agora_uid)
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  if b.host_a_id is null then
    update public.live_battles
      set host_a_id = trim(p_user_id),
          host_a_agora_uid = au
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  if b.host_b_id is null then
    update public.live_battles
      set host_b_id = trim(p_user_id),
          host_b_agora_uid = au
    where battle_id = trim(p_battle_id)
    returning * into b;
    return b;
  end if;

  raise exception 'battle_full';
end;
$$;
revoke all on function public.battle_claim_host(text, text, text, bigint) from public;
grant execute on function public.battle_claim_host(text, text, text, bigint) to service_role;
