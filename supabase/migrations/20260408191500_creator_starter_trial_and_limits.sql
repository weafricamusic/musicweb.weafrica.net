-- Align starter creator plans with launch policy:
-- - 7-day free trial for new artist/dj starters
-- - 5 uploads for songs/mixes and 5 videos
-- - battles enabled (usage/duration limits enforced in Edge API)

update public.subscription_plans
set
  trial_eligible = true,
  trial_duration_days = 7,
  features = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(features, '{}'::jsonb),
          '{creator,uploads,songs}',
          to_jsonb(5),
          true
        ),
        '{creator,uploads,videos}',
        to_jsonb(5),
        true
      ),
      '{creator,live,battles}',
      to_jsonb(true),
      true
    ),
    '{battles,enabled}',
    to_jsonb(true),
    true
  ),
  perks = jsonb_set(
    jsonb_set(
      jsonb_set(
        coalesce(perks, '{}'::jsonb),
        '{creator,uploads,songs}',
        to_jsonb(5),
        true
      ),
      '{creator,uploads,videos}',
      to_jsonb(5),
      true
    ),
    '{creator,live,battles}',
    to_jsonb(true),
    true
  ),
  updated_at = now()
where lower(plan_id) in ('artist_starter', 'artist_free');

update public.subscription_plans
set
  trial_eligible = true,
  trial_duration_days = 7,
  features = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(features, '{}'::jsonb),
            '{creator,uploads,mixes}',
            to_jsonb(5),
            true
          ),
          '{creator,uploads,songs}',
          to_jsonb(5),
          true
        ),
        '{creator,uploads,videos}',
        to_jsonb(5),
        true
      ),
      '{creator,live,battles}',
      to_jsonb(true),
      true
    ),
    '{battles,enabled}',
    to_jsonb(true),
    true
  ),
  perks = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(perks, '{}'::jsonb),
          '{creator,uploads,mixes}',
          to_jsonb(5),
          true
        ),
        '{creator,uploads,songs}',
        to_jsonb(5),
        true
      ),
      '{creator,uploads,videos}',
      to_jsonb(5),
      true
    ),
    '{creator,live,battles}',
    to_jsonb(true),
    true
  ),
  updated_at = now()
where lower(plan_id) in ('dj_starter', 'dj_free');
