-- Launch coin packs (March 2026)
-- Extend public.coins for admin/catalog use and keep public.coin_packages
-- aligned for the consumer checkout flow.

alter table public.coins
  add column if not exists coin_amount bigint,
  add column if not exists usd_reference_price numeric(10,2),
  add column if not exists sort_order integer not null default 100;

update public.coins
set
  coin_amount = coalesce(coin_amount,
    case code
      when 'bronze' then 100
      when 'silver' then 500
      when 'gold' then 1000
      when 'diamond' then 5000
      else greatest(value_mwk, 1)
    end
  ),
  sort_order = coalesce(sort_order,
    case code
      when 'bronze' then 10
      when 'silver' then 20
      when 'gold' then 30
      when 'diamond' then 40
      else 100
    end
  )
where coin_amount is null
   or sort_order is null;

update public.coins
set coin_amount = greatest(value_mwk, 1)
where coin_amount is null;

alter table public.coins
  alter column coin_amount set not null;

alter table public.coins
  drop constraint if exists coins_coin_amount_positive;

alter table public.coins
  add constraint coins_coin_amount_positive check (coin_amount > 0);

insert into public.coins (code, name, value_mwk, coin_amount, usd_reference_price, sort_order, status)
values
  ('coins_100', '100 Coins', 1720, 100, 0.99, 10, 'active'),
  ('coins_500', '500 Coins', 7790, 500, 4.49, 20, 'active'),
  ('coins_1000', '1000 Coins', 13860, 1000, 7.99, 30, 'active'),
  ('coins_5000', '5000 Coins', 60700, 5000, 34.99, 40, 'active')
on conflict (code) do update set
  name = excluded.name,
  value_mwk = excluded.value_mwk,
  coin_amount = excluded.coin_amount,
  usd_reference_price = excluded.usd_reference_price,
  sort_order = excluded.sort_order,
  status = excluded.status,
  updated_at = now();

update public.coins
set
  status = 'disabled',
  updated_at = now()
where code in ('bronze', 'silver', 'gold', 'diamond');

-- Keep the consumer checkout catalog in sync with the launch packs.
insert into public.coin_packages (id, title, coins, bonus_coins, price, currency, active, sort_order)
values
  ('coins_100', '100 Coins', 100, 0, 1720, 'MWK', true, 10),
  ('coins_500', '500 Coins', 500, 0, 7790, 'MWK', true, 20),
  ('coins_1000', '1000 Coins', 1000, 0, 13860, 'MWK', true, 30),
  ('coins_5000', '5000 Coins', 5000, 0, 60700, 'MWK', true, 40)
on conflict (id) do update set
  title = excluded.title,
  coins = excluded.coins,
  bonus_coins = excluded.bonus_coins,
  price = excluded.price,
  currency = excluded.currency,
  active = excluded.active,
  sort_order = excluded.sort_order,
  updated_at = now();

update public.coin_packages
set
  active = false,
  updated_at = now()
where id in ('starter', 'silver', 'gold', 'platinum');

create index if not exists coins_status_sort_idx
  on public.coins (status, sort_order);

notify pgrst, 'reload schema';
