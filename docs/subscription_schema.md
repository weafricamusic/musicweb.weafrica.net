# Subscription Schema

## Canonical source of truth

- Runtime plan catalog: `public.subscription_plans`
- Runtime plan API: `GET /api/subscriptions/plans`
- Runtime entitlement API: `GET /api/subscriptions/me`
- Canonical entitlement payloads live in JSONB columns:
  - `features`: full gating contract
  - `perks`: lighter-weight experience contract used by app and admin surfaces

## Canonical plan fields

The current canonical `subscription_plans` contract is:

- `plan_id text`
- `audience text`
- `name text`
- `price_mwk integer`
- `billing_interval text`
- `currency text`
- `active boolean`
- `is_active boolean`
- `sort_order integer`
- `features jsonb`
- `perks jsonb`
- `marketing jsonb`
- `trial_eligible boolean`
- `trial_duration_days integer`
- `updated_at timestamptz`

## Launch catalog

| Audience | Plan ID | Price MWK | Sort Order | Trial |
| --- | --- | ---: | ---: | --- |
| consumer | `free` | 0 | 10 | none |
| consumer | `premium` | 4000 | 20 | none |
| consumer | `platinum` | 8500 | 30 | none |
| artist | `artist_starter` | 0 | 110 | 30-day starter trial metadata |
| artist | `artist_pro` | 6000 | 120 | none |
| artist | `artist_premium` | 12500 | 130 | none |
| dj | `dj_starter` | 0 | 210 | 30-day starter trial metadata |
| dj | `dj_pro` | 8000 | 220 | none |
| dj | `dj_premium` | 15000 | 230 | none |

## Trial metadata rules

- `artist_starter` and `dj_starter` are the only plans with `trial_eligible = true`
- Starter plans currently expose `trial_duration_days = 30`
- All other canonical plans use `trial_eligible = false` and `trial_duration_days = 0`
- Trial policy is one-time per role; this document only covers plan metadata, not trial activation flows

## API expectations

`GET /api/subscriptions/plans` returns plan rows with:

- `plan_id`
- `audience`
- `name`
- `price_mwk`
- `billing_interval`
- `currency`
- `features`
- `perks`
- `marketing`
- `trial_eligible`
- `trial_duration_days`

`GET /api/subscriptions/me` returns:

- `plan_id`
- `status`
- `entitlements.features`
- `entitlements.perks`

It may also include plan-level metadata such as `audience`, `trial_eligible`, and `trial_duration_days`. Flutter parsing keeps these optional and falls back to canonical defaults when omitted.

## Compatibility rules

- Legacy aliases `vip` and `vip_listener` normalize to `platinum`
- Main runtime should not bury `perks` under `features.perks`
- Audience fallback is inferred from plan ID when older payloads omit `audience`