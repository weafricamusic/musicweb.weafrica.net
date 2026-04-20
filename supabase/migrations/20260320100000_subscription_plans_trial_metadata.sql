-- Adds canonical trial metadata to subscription_plans for existing environments.

alter table public.subscription_plans
	add column if not exists trial_eligible boolean,
	add column if not exists trial_duration_days integer;

alter table public.subscription_plans
	alter column trial_eligible set default false,
	alter column trial_duration_days set default 0;

update public.subscription_plans
set
	trial_eligible = case
		when lower(coalesce(plan_id, '')) in ('artist_starter', 'dj_starter') then true
		else false
	end,
	trial_duration_days = case
		when lower(coalesce(plan_id, '')) in ('artist_starter', 'dj_starter') then 30
		else 0
	end,
	updated_at = now()
where lower(coalesce(plan_id, '')) in (
	'free',
	'premium',
	'platinum',
	'artist_starter',
	'artist_pro',
	'artist_premium',
	'dj_starter',
	'dj_pro',
	'dj_premium'
)
or trial_eligible is null
or trial_duration_days is null;

update public.subscription_plans
set
	trial_eligible = coalesce(trial_eligible, false),
	trial_duration_days = greatest(coalesce(trial_duration_days, 0), 0),
	updated_at = coalesce(updated_at, now())
where true;

alter table public.subscription_plans
	alter column trial_eligible set not null,
	alter column trial_duration_days set not null;
