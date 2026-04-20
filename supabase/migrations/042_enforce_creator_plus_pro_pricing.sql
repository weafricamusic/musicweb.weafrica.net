-- Enforce final creator pricing for Artist and DJ plans
-- Plus: MK 30,000 / month
-- Pro:  MK 50,000 / month
--
-- Rationale:
-- Earlier migrations may have been edited after deploy; this migration makes the
-- remote state deterministic and idempotent.

insert into subscription_plans (role, plan, price, currency, billing_interval)
values
  ('artist', 'plus', 30000, 'MWK', 'month'),
  ('artist', 'pro', 50000, 'MWK', 'month'),
  ('dj', 'plus', 30000, 'MWK', 'month'),
  ('dj', 'pro', 50000, 'MWK', 'month')
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency;
