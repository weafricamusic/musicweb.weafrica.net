-- Ensure consumer subscription plans are compatible with the newer unique index
-- (role, plan, billing_interval) introduced in 035_update_artist_subscription_plans.sql.
--
-- Why:
-- - Older seed data only inserted consumer plans for (role, plan) and can be missing
--   when environments were provisioned after the unique index change.
-- - The app reads plans by (role, plan, billing_interval); missing rows makes the
--   consumer subscription flow appear “not real”.

-- Consumer plans (example pricing; adjust as needed)
-- Premium: 1,000 MWK / month; 10,000 MWK / year

insert into subscription_plans (role, plan, price, currency, billing_interval, features)
values
  (
    'consumer','free',0,'MWK','month',
    '{
      "ads": true,
      "badge": "FREE"
    }'::jsonb
  ),
  (
    'consumer','free',0,'MWK','year',
    '{
      "ads": true,
      "badge": "FREE"
    }'::jsonb
  ),
  (
    'consumer','premium',1000,'MWK','month',
    '{
      "ads": false,
      "skips": "unlimited",
      "votes": true,
      "offline": true,
      "badge": "PREMIUM"
    }'::jsonb
  ),
  (
    'consumer','premium',10000,'MWK','year',
    '{
      "ads": false,
      "skips": "unlimited",
      "votes": true,
      "offline": true,
      "badge": "PREMIUM"
    }'::jsonb
  )
on conflict (role, plan, billing_interval)
do update set
  price = excluded.price,
  currency = excluded.currency,
  features = excluded.features;
