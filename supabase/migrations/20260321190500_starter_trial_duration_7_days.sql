-- Align starter trials with the 7-day journey spec.
-- NOTE: Do not edit earlier migrations; apply a forward-only correction.

update public.subscription_plans
set
  trial_duration_days = 7,
  updated_at = now()
where lower(coalesce(plan_id, '')) in ('artist_starter', 'dj_starter')
  and coalesce(trial_eligible, false) = true
  and coalesce(trial_duration_days, 0) <> 7;
