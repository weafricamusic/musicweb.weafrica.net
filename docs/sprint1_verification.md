# Sprint 1 Verification

## Database

Apply the canonical subscription migrations, including:

- `supabase/migrations/20260319143000_subscription_plans_four_structure_blueprint.sql`
- `supabase/migrations/20260320100000_subscription_plans_trial_metadata.sql`

Verify in SQL:

```sql
select
  audience,
  plan_id,
  price_mwk,
  sort_order,
  trial_eligible,
  trial_duration_days
from public.subscription_plans
where plan_id in (
  'free', 'premium', 'platinum',
  'artist_starter', 'artist_pro', 'artist_premium',
  'dj_starter', 'dj_pro', 'dj_premium'
)
order by sort_order;
```

Expected result:

- 9 canonical plans
- sort order bands `10/20/30`, `110/120/130`, `210/220/230`
- only `artist_starter` and `dj_starter` are trial-eligible

## Edge API

Run the public plan smoke test:

```bash
dart run tool/subscriptions_smoke_test.dart tool/supabase.env.json
```

Expected assertions:

- no legacy plan IDs leak into the launch catalog
- every returned plan has `audience`
- every returned plan has `perks`
- starter plans expose `trial_eligible = true` and `trial_duration_days = 30`

Optional authenticated check:

```bash
dart run tool/subscription_me_smoke_test.dart tool/supabase.env.json <firebase_id_token> <expected_plan_id>
```

## Flutter parsing

Run targeted tests:

```bash
flutter test test/subscription_plan_matching_test.dart
flutter test test/subscription_me_parsing_test.dart
```

Expected assertions:

- canonical plan ID normalization still works
- `SubscriptionPlan` parses `audience`, `perks`, and starter trial metadata
- `SubscriptionMe` keeps optional audience/trial metadata forward-compatible

## Admin dashboard

Open the subscription plans editor and verify:

- plans are grouped by audience
- each plan row shows the correct trial badge
- editing `features` and `perks` works independently
- `sort_order`, `audience`, and trial fields persist after save