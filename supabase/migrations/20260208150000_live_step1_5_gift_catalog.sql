-- STEP 1.5 (GIFTS CATALOG)
-- Real, server-managed gift catalog (no demo).

create table if not exists public.live_gifts (
  id text primary key,
  name text not null,
  coin_cost bigint not null check (coin_cost > 0),
  icon_name text not null,
  enabled boolean not null default true,
  sort_order int not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.live_gifts enable row level security;

do $$
begin
  create policy "Public read live gifts catalog" on public.live_gifts
    for select
    to anon, authenticated
    using (enabled = true);
exception
  when duplicate_object then null;
end $$;

-- Seed default gifts (id matches gift_id in live_gift_events)
insert into public.live_gifts (id, name, coin_cost, icon_name, enabled, sort_order)
values
  ('fire', 'Fire', 10, 'local_fire_department', true, 10),
  ('love', 'Love', 15, 'favorite', true, 20),
  ('crown', 'Crown', 50, 'workspace_premium', true, 30),
  ('rocket', 'Rocket', 120, 'rocket_launch', true, 40)
on conflict (id) do update set
  name = excluded.name,
  coin_cost = excluded.coin_cost,
  icon_name = excluded.icon_name,
  enabled = excluded.enabled,
  sort_order = excluded.sort_order,
  updated_at = now();
