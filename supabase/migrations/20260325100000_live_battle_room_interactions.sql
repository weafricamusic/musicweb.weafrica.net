-- Battle room interactions for the current live_battles flow.
--
-- Adds:
-- - battle_requests: queue of users asking to challenge next
-- - battle_votes: one audience vote per user per battle
-- - battle_chat: battle-scoped chat separate from generic live_messages
-- - helper RPCs used by the Flutter battle room UI

create extension if not exists pgcrypto;

create table if not exists public.battle_requests (
  id uuid primary key default gen_random_uuid(),
  battle_id text not null references public.live_battles(battle_id) on delete cascade,
  requester_id text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (battle_id, requester_id)
);

create index if not exists idx_battle_requests_battle_id
  on public.battle_requests (battle_id);
create index if not exists idx_battle_requests_status
  on public.battle_requests (status);

create table if not exists public.battle_votes (
  id uuid primary key default gen_random_uuid(),
  battle_id text not null references public.live_battles(battle_id) on delete cascade,
  user_id text not null,
  voted_for text not null,
  created_at timestamptz not null default now(),
  unique (battle_id, user_id)
);

-- Compatibility: older schemas created `public.battle_votes` for `public.battles`
-- with `battle_id uuid` and without `voted_for`. Ensure the current live_battles
-- flow can write/query votes safely.
do $$
begin
  if to_regclass('public.battle_votes') is null then
    return;
  end if;

  -- If battle_id is UUID, preserve it as battle_uuid and introduce battle_id TEXT.
  if exists (
    select 1
    from pg_attribute a
    where a.attrelid = 'public.battle_votes'::regclass
      and a.attname = 'battle_id'
      and a.attisdropped = false
      and a.atttypid = 'uuid'::regtype
  ) then
    alter table public.battle_votes drop constraint if exists battle_votes_battle_id_fkey;

    drop index if exists public.uq_battle_votes_battle_user;
    drop index if exists public.idx_battle_votes_battle;
    drop index if exists public.idx_battle_votes_battle_id;

    alter table public.battle_votes rename column battle_id to battle_uuid;
    alter table public.battle_votes alter column battle_uuid drop not null;

    alter table public.battle_votes add column if not exists battle_id text;
    update public.battle_votes
      set battle_id = battle_uuid::text
      where battle_id is null and battle_uuid is not null;
    alter table public.battle_votes alter column battle_id set not null;

    create unique index if not exists uq_battle_votes_battle_user
      on public.battle_votes (battle_id, user_id);
  end if;

  alter table public.battle_votes
    add column if not exists voted_for text,
    add column if not exists created_at timestamptz not null default now();
exception
  when undefined_table then null;
end $$;

create index if not exists idx_battle_votes_battle_id
  on public.battle_votes (battle_id);
create index if not exists idx_battle_votes_voted_for
  on public.battle_votes (battle_id, voted_for);

create table if not exists public.battle_chat (
  id uuid primary key default gen_random_uuid(),
  battle_id text not null references public.live_battles(battle_id) on delete cascade,
  user_id text not null,
  user_name text,
  message text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_battle_chat_battle_id
  on public.battle_chat (battle_id);
create index if not exists idx_battle_chat_created_at
  on public.battle_chat (created_at desc);

create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_battle_requests_updated_at on public.battle_requests;
create trigger trg_battle_requests_updated_at
before update on public.battle_requests
for each row execute function public.update_updated_at_column();

create or replace function public.has_active_battle(p_user_id text)
returns boolean
language plpgsql
security definer
as $$
declare
  active boolean;
begin
  select exists (
    select 1
    from public.live_battles b
    where (
      coalesce(nullif(btrim(b.host_a_id), ''), '') = coalesce(nullif(btrim(p_user_id), ''), '')
      or coalesce(nullif(btrim(b.host_b_id), ''), '') = coalesce(nullif(btrim(p_user_id), ''), '')
    )
      and b.status in ('waiting', 'countdown', 'live', 'ready')
  ) into active;

  return coalesce(active, false);
end;
$$;

create or replace function public.add_vote(
  p_battle_id text,
  p_user_id text,
  p_voted_for text
)
returns void
language plpgsql
security definer
as $$
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_user_id is null or length(trim(p_user_id)) = 0 then
    raise exception 'user_id_required';
  end if;
  if p_voted_for is null or length(trim(p_voted_for)) = 0 then
    raise exception 'voted_for_required';
  end if;

  insert into public.battle_votes (battle_id, user_id, voted_for, created_at)
  values (trim(p_battle_id), trim(p_user_id), trim(p_voted_for), now())
  on conflict (battle_id, user_id) do update set
    voted_for = excluded.voted_for,
    created_at = now();
end;
$$;

create or replace function public.add_battle_request(
  p_battle_id text,
  p_requester_id text
)
returns void
language plpgsql
security definer
as $$
begin
  if p_battle_id is null or length(trim(p_battle_id)) = 0 then
    raise exception 'battle_id_required';
  end if;
  if p_requester_id is null or length(trim(p_requester_id)) = 0 then
    raise exception 'requester_id_required';
  end if;

  if public.has_active_battle(trim(p_requester_id)) then
    return;
  end if;

  if (
    select count(*)
    from public.battle_requests
    where battle_id = trim(p_battle_id)
      and status = 'pending'
  ) >= 20 then
    return;
  end if;

  insert into public.battle_requests (battle_id, requester_id, status, created_at, updated_at)
  values (trim(p_battle_id), trim(p_requester_id), 'pending', now(), now())
  on conflict (battle_id, requester_id) do update set
    status = 'pending',
    updated_at = now();
end;
$$;

create or replace function public.accept_next_request(p_battle_id text)
returns table (
  requester_id text,
  request_id uuid
)
language plpgsql
security definer
as $$
declare
  next_request public.battle_requests%rowtype;
begin
  select * into next_request
  from public.battle_requests
  where battle_id = trim(p_battle_id)
    and status = 'pending'
  order by created_at asc
  limit 1
  for update skip locked;

  if next_request.id is null then
    return;
  end if;

  update public.battle_requests
  set status = 'accepted'
  where id = next_request.id;

  requester_id := next_request.requester_id;
  request_id := next_request.id;
  return next;
end;
$$;

create or replace function public.clear_battle_queue(p_battle_id text)
returns void
language plpgsql
security definer
as $$
begin
  delete from public.battle_requests
  where battle_id = trim(p_battle_id);
end;
$$;

create or replace function public.reject_battle_request(p_request_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  update public.battle_requests
  set status = 'rejected'
  where id = p_request_id;
end;
$$;

alter table public.battle_requests enable row level security;
alter table public.battle_votes enable row level security;
alter table public.battle_chat enable row level security;

drop policy if exists "Anyone can view battle_requests" on public.battle_requests;
create policy "Anyone can view battle_requests"
  on public.battle_requests
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Users can create requests" on public.battle_requests;
create policy "Users can create requests"
  on public.battle_requests
  for insert
  to authenticated
  with check (auth.uid()::text = requester_id);

drop policy if exists "Request owners can update their requests" on public.battle_requests;
create policy "Request owners can update their requests"
  on public.battle_requests
  for update
  to authenticated
  using (auth.uid()::text = requester_id)
  with check (auth.uid()::text = requester_id);

drop policy if exists "Anyone can view votes" on public.battle_votes;
create policy "Anyone can view votes"
  on public.battle_votes
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Users can vote once" on public.battle_votes;
create policy "Users can vote once"
  on public.battle_votes
  for insert
  to authenticated
  with check (auth.uid()::text = user_id);

drop policy if exists "Users can update their own vote" on public.battle_votes;
create policy "Users can update their own vote"
  on public.battle_votes
  for update
  to authenticated
  using (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);

drop policy if exists "Anyone can view battle chat" on public.battle_chat;
create policy "Anyone can view battle chat"
  on public.battle_chat
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Authenticated users can post battle chat" on public.battle_chat;
create policy "Authenticated users can post battle chat"
  on public.battle_chat
  for insert
  to authenticated
  with check (auth.uid()::text = user_id);

grant select, insert, update on public.battle_requests to authenticated;
grant select on public.battle_requests to anon;
grant select, insert, update on public.battle_votes to authenticated;
grant select on public.battle_votes to anon;
grant select, insert on public.battle_chat to authenticated;
grant select on public.battle_chat to anon;

grant execute on function public.has_active_battle(text) to authenticated, service_role;
grant execute on function public.add_vote(text, text, text) to authenticated, service_role;
grant execute on function public.add_battle_request(text, text) to authenticated, service_role;
grant execute on function public.accept_next_request(text) to authenticated, service_role;
grant execute on function public.clear_battle_queue(text) to authenticated, service_role;
grant execute on function public.reject_battle_request(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';