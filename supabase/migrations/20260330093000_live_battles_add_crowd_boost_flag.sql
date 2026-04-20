-- Persist host-controlled crowd boost state for live battle rooms.

alter table public.live_battles
  add column if not exists crowd_boost_enabled boolean not null default false;