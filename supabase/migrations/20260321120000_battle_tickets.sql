-- Battle Tickets (Live Monetization)
--
-- Stores a single ticket configuration per live battle.
-- Writes are intended to be performed via Edge Functions (service_role),
-- not directly from clients.

create extension if not exists pgcrypto;

-- Shared helper for updated_at.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.battle_tickets (
  id uuid primary key default gen_random_uuid(),
  battle_id text not null,
  channel_id text not null,
  host_user_id text not null,
  host_role text not null,

  price_coins int not null default 0,
  quantity_total int not null,
  quantity_sold int not null default 0,
  sales_enabled boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint battle_tickets_host_role_check
    check (host_role in ('artist','dj')),
  constraint battle_tickets_price_nonneg
    check (price_coins >= 0),
  constraint battle_tickets_quantity_bounds
    check (quantity_total > 0 and quantity_sold >= 0 and quantity_sold <= quantity_total)
);

-- Tie tickets to an existing battle if the battle table exists.
do $$
begin
  if to_regclass('public.live_battles') is not null then
    if not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.battle_tickets'::regclass
        and conname = 'battle_tickets_battle_id_fk'
    ) then
      alter table public.battle_tickets
        add constraint battle_tickets_battle_id_fk
        foreign key (battle_id)
        references public.live_battles(battle_id)
        on delete cascade;
    end if;
  end if;
end $$;

create unique index if not exists battle_tickets_battle_id_uniq
  on public.battle_tickets (battle_id);

create index if not exists battle_tickets_host_user_id_idx
  on public.battle_tickets (host_user_id);

create index if not exists battle_tickets_created_at_idx
  on public.battle_tickets (created_at desc);

drop trigger if exists trg_battle_tickets_set_updated_at on public.battle_tickets;
create trigger trg_battle_tickets_set_updated_at
  before update on public.battle_tickets
  for each row
  execute function public.tg_set_updated_at();

alter table public.battle_tickets enable row level security;

drop policy if exists battle_tickets_select_all on public.battle_tickets;
create policy battle_tickets_select_all
  on public.battle_tickets
  for select
  to anon, authenticated
  using (true);

grant select on public.battle_tickets to anon, authenticated;

notify pgrst, 'reload schema';
