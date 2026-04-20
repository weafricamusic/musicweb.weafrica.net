-- STEP 2.1 — 1 vs 1 Battle foundation
-- - Stores battle state (waiting/live/ended)
-- - Enforces max 2 hosts (broadcasters)

create table if not exists public.live_battles (
	battle_id text primary key,
	channel_id text not null unique,
	status text not null default 'waiting' check (status in ('waiting','live','ended')),

	host_a_id text,
	host_b_id text,

	host_a_ready boolean not null default false,
	host_b_ready boolean not null default false,

	started_at timestamptz,
	ended_at timestamptz,

	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create or replace function public._touch_updated_at()
returns trigger
language plpgsql
as $$
begin
	new.updated_at = now();
	return new;
end;
$$;
drop trigger if exists trg_live_battles_touch on public.live_battles;
create trigger trg_live_battles_touch
before update on public.live_battles
for each row execute function public._touch_updated_at();
-- Allow anyone to read battle state (needed for audience UI).
alter table public.live_battles enable row level security;
drop policy if exists "live_battles_select_all" on public.live_battles;
create policy "live_battles_select_all"
	on public.live_battles
	for select
	to anon, authenticated
	using (true);
-- Claim a host slot for a battle (max 2).
-- Intentionally restricted to service_role (Edge function).
create or replace function public.battle_claim_host(
	p_battle_id text,
	p_channel_id text,
	p_user_id text
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
	b public.live_battles;
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

	if b.host_a_id = trim(p_user_id) or b.host_b_id = trim(p_user_id) then
		return b;
	end if;

	if b.host_a_id is null then
		update public.live_battles
			set host_a_id = trim(p_user_id)
		where battle_id = trim(p_battle_id)
		returning * into b;
		return b;
	end if;

	if b.host_b_id is null then
		update public.live_battles
			set host_b_id = trim(p_user_id)
		where battle_id = trim(p_battle_id)
		returning * into b;
		return b;
	end if;

	raise exception 'battle_full';
end;
$$;
-- Set ready/unready for a host. Auto-start when both ready.
create or replace function public.battle_set_ready(
	p_battle_id text,
	p_user_id text,
	p_ready boolean
)
returns public.live_battles
language plpgsql
security definer
as $$
declare
	b public.live_battles;
	ready boolean := coalesce(p_ready, true);
begin
	if p_battle_id is null or length(trim(p_battle_id)) = 0 then
		raise exception 'battle_id_required';
	end if;
	if p_user_id is null or length(trim(p_user_id)) = 0 then
		raise exception 'user_id_required';
	end if;

	select * into b
	from public.live_battles
	where battle_id = trim(p_battle_id)
	for update;

	if not found then
		raise exception 'battle_not_found';
	end if;

	if b.host_a_id = trim(p_user_id) then
		update public.live_battles
			set host_a_ready = ready
		where battle_id = trim(p_battle_id)
		returning * into b;
	elsif b.host_b_id = trim(p_user_id) then
		update public.live_battles
			set host_b_ready = ready
		where battle_id = trim(p_battle_id)
		returning * into b;
	else
		raise exception 'not_a_host';
	end if;

	if b.status = 'waiting' and b.host_a_ready and b.host_b_ready then
		update public.live_battles
			set status = 'live', started_at = coalesce(started_at, now())
		where battle_id = trim(p_battle_id)
		returning * into b;
	end if;

	return b;
end;
$$;
revoke all on function public.battle_claim_host(text, text, text) from public;
revoke all on function public.battle_set_ready(text, text, boolean) from public;
grant execute on function public.battle_claim_host(text, text, text) to service_role;
grant execute on function public.battle_set_ready(text, text, boolean) to service_role;
