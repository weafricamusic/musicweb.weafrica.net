# WeAfrica DJ AI — ML v1 (Hybrid Policy)

This folder contains a lightweight, **offline** learning workflow for the DJ AI.

## What gets logged

Every call to `POST /api/dj/next` inserts a row into `public.dj_ai_events` (Supabase).

This gives you training data like:
- `style`, `current_song_bpm`, `likes_per_min`, `coins_per_min`, `viewers_change`
- `pressure_state`, `rule_decision`, `ml_decision`, final `decision`, `next_song_id`
- optional `battle_id`, `user_id`

## How ML works in v1

The Edge Function can optionally consult a small lookup table `public.dj_ai_policy`.

- If `WEAFRICA_DJ_AI_USE_ML=true` and a policy row exists with `confidence >= 0.7`, the API will use that decision.
- Otherwise it falls back to the rule engine (pressure + style logic).

This is the intended hybrid approach: safe + explainable.

## Export events from Supabase

Export `dj_ai_events` to CSV (any method works):
- Supabase dashboard table export
- SQL to CSV via psql

Make sure the CSV includes at least:
- `style`, `pressure_state`, `current_song_bpm`, `likes_per_min`, `coins_per_min`, `viewers_change`, `decision`

Optional but recommended:
- `outcome` (e.g. `win|lose|draw`) so the learner can weight decisions by results.

## Build a policy from events

Run:

```bash
python3 tool/dj_ai_ml/build_policy_from_events.py \
  --in dj_ai_events.csv \
  --out dj_ai_policy_upserts.sql
```

Then apply the SQL in Supabase (Dashboard SQL editor or `psql`).

## Notes

- The policy uses **binning** (same bins as the Edge Function) to keep the table small.
- You can regenerate and upsert the policy weekly as your battles data grows.
