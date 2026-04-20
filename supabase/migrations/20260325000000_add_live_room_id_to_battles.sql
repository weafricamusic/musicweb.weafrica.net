alter table public.live_battles
  add column if not exists live_room_id uuid;

create index if not exists idx_live_battles_live_room_id
  on public.live_battles (live_room_id);
