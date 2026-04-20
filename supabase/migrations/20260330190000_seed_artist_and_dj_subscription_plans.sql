-- Seed Artist + DJ subscription plans so the admin dashboard can manage creator subscriptions.
--
-- This migration is idempotent and tolerant of schema drift:
-- - Some deployments have legacy columns (role, plan, price, currency)
-- - Some deployments used restrictive plan_id check constraints
-- - Some deployments used audience values like 'creator'/'both'

create extension if not exists pgcrypto;

-- Ensure baseline columns exist (safe no-ops if already present).
alter table public.subscription_plans
	add column if not exists plan_id text,
	add column if not exists audience text,
	add column if not exists name text,
	add column if not exists price_mwk integer,
	add column if not exists billing_interval text,
	add column if not exists currency text,
	add column if not exists active boolean,
	add column if not exists is_active boolean,
	add column if not exists sort_order integer,
	add column if not exists features jsonb,
	add column if not exists marketing jsonb,
	add column if not exists updated_at timestamptz;

-- Backfill safe defaults.
update public.subscription_plans
set
	currency = coalesce(nullif(trim(currency), ''), 'MWK'),
	billing_interval = coalesce(nullif(trim(billing_interval), ''), 'month'),
	price_mwk = coalesce(price_mwk, 0),
	sort_order = coalesce(sort_order, 0),
	active = coalesce(active, is_active, true),
	is_active = coalesce(is_active, active, true),
	audience = coalesce(nullif(trim(audience), ''), 'consumer'),
	updated_at = coalesce(updated_at, now())
where
	currency is null
	or billing_interval is null
	or price_mwk is null
	or sort_order is null
	or active is null
	or is_active is null
	or audience is null
	or trim(audience) = ''
	or updated_at is null;

-- Relax audience constraints across drifted deployments.
do $$
declare
	c record;
begin
	for c in (
		select con.conname
		from pg_constraint con
		join pg_class rel on rel.oid = con.conrelid
		join pg_namespace nsp on nsp.oid = rel.relnamespace
		where nsp.nspname = 'public'
			and rel.relname = 'subscription_plans'
			and con.contype = 'c'
			and pg_get_constraintdef(con.oid) ilike '%audience%'
	) loop
		execute format('alter table public.subscription_plans drop constraint if exists %I', c.conname);
	end loop;

	begin
		execute $sql$
			alter table public.subscription_plans
				add constraint subscription_plans_audience_check
				check (audience is null or audience in ('consumer','creator','both','artist','dj'));
		$sql$;
	exception when duplicate_object then
		null;
	end;
end $$;

-- Remove legacy plan_id whitelist constraint(s) that block creator IDs.
alter table public.subscription_plans
	drop constraint if exists subscription_plans_plan_id_check;

do $$
declare
	c record;
begin
	for c in (
		select con.conname
		from pg_constraint con
		join pg_class rel on rel.oid = con.conrelid
		join pg_namespace nsp on nsp.oid = rel.relnamespace
		where nsp.nspname = 'public'
			and rel.relname = 'subscription_plans'
			and con.contype = 'c'
			and pg_get_constraintdef(con.oid) ilike '%plan_id%'
			and pg_get_constraintdef(con.oid) ilike '%in%'
	) loop
		execute format('alter table public.subscription_plans drop constraint if exists %I', c.conname);
	end loop;
end $$;

-- Seed/update creator plans.
do $$
declare
	has_role boolean;
	has_plan boolean;
	has_price boolean;
	has_currency boolean;
begin
	select exists (
		select 1 from information_schema.columns
		where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'role'
	) into has_role;

	select exists (
		select 1 from information_schema.columns
		where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'plan'
	) into has_plan;

	select exists (
		select 1 from information_schema.columns
		where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'price'
	) into has_price;

	select exists (
		select 1 from information_schema.columns
		where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'currency'
	) into has_currency;

	if has_role and has_plan and has_price and has_currency then
		execute $sql$
			insert into public.subscription_plans (
				plan_id,
				audience,
				name,
				price_mwk,
				billing_interval,
				currency,
				active,
				is_active,
				sort_order,
				features,
				marketing,
				role,
				plan,
				price
			) values
				(
					'artist_starter',
					'artist',
					'Artist Starter',
					0,
					'month',
					'MWK',
					true,
					true,
					110,
					'{"creator":{"tier":"starter","uploads":{"songs_per_month":5},"analytics":"basic"}}'::jsonb,
					'{"tagline":"Start distributing your music.","bullets":["Upload up to 5 songs","Basic analytics","Creator tools"]}'::jsonb,
					'artist',
					'artist_starter',
					0
				),
				(
					'artist_premium',
					'artist',
					'Artist Premium',
					5000,
					'month',
					'MWK',
					true,
					true,
					130,
					'{"creator":{"tier":"premium","uploads":{"songs_per_month":10},"analytics":"standard","monetization":true}}'::jsonb,
					'{"tagline":"Grow your fanbase.","bullets":["Upload up to 10 songs","Standard analytics","Monetization tools"]}'::jsonb,
					'artist',
					'artist_premium',
					5000
				),
				(
					'artist_pro',
					'artist',
					'Artist Pro',
					15000,
					'month',
					'MWK',
					true,
					true,
					120,
					'{"creator":{"tier":"pro","uploads":{"songs_per_month":"unlimited"},"analytics":"advanced","monetization":true}}'::jsonb,
					'{"tagline":"Unlimited uploads + advanced analytics.","bullets":["Unlimited uploads","Advanced analytics","Priority support"]}'::jsonb,
					'artist',
					'artist_pro',
					15000
				),
				(
					'dj_starter',
					'dj',
					'DJ Starter',
					0,
					'month',
					'MWK',
					true,
					true,
					210,
					'{"creator":{"tier":"starter","uploads":{"mixes_per_month":4},"analytics":"basic"}}'::jsonb,
					'{"tagline":"Start publishing your mixes.","bullets":["Upload up to 4 mixes","Basic analytics","DJ tools"]}'::jsonb,
					'dj',
					'dj_starter',
					0
				),
				(
					'dj_premium',
					'dj',
					'DJ Premium',
					5000,
					'month',
					'MWK',
					true,
					true,
					230,
					'{"creator":{"tier":"premium","uploads":{"mixes_per_month":10},"analytics":"standard","monetization":true}}'::jsonb,
					'{"tagline":"More uploads + monetization.","bullets":["Upload up to 10 mixes","Standard analytics","Monetization tools"]}'::jsonb,
					'dj',
					'dj_premium',
					5000
				),
				(
					'dj_pro',
					'dj',
					'DJ Pro',
					15000,
					'month',
					'MWK',
					true,
					true,
					220,
					'{"creator":{"tier":"pro","uploads":{"mixes_per_month":"unlimited"},"analytics":"advanced","monetization":true}}'::jsonb,
					'{"tagline":"Unlimited uploads + advanced analytics.","bullets":["Unlimited uploads","Advanced analytics","Priority support"]}'::jsonb,
					'dj',
					'dj_pro',
					15000
				)
			on conflict (plan_id) do update set
				audience = excluded.audience,
				name = excluded.name,
				price_mwk = excluded.price_mwk,
				billing_interval = excluded.billing_interval,
				currency = excluded.currency,
				active = excluded.active,
				is_active = excluded.is_active,
				sort_order = excluded.sort_order,
				features = excluded.features,
				marketing = excluded.marketing,
				role = excluded.role,
				plan = excluded.plan,
				price = excluded.price,
				updated_at = now();
		$sql$;
	else
		execute $sql$
			insert into public.subscription_plans (
				plan_id,
				audience,
				name,
				price_mwk,
				billing_interval,
				currency,
				active,
				is_active,
				sort_order,
				features,
				marketing
			) values
				(
					'artist_starter',
					'artist',
					'Artist Starter',
					0,
					'month',
					'MWK',
					true,
					true,
					110,
					'{"creator":{"tier":"starter","uploads":{"songs_per_month":5},"analytics":"basic"}}'::jsonb,
					'{"tagline":"Start distributing your music.","bullets":["Upload up to 5 songs","Basic analytics","Creator tools"]}'::jsonb
				),
				(
					'artist_premium',
					'artist',
					'Artist Premium',
					5000,
					'month',
					'MWK',
					true,
					true,
					130,
					'{"creator":{"tier":"premium","uploads":{"songs_per_month":10},"analytics":"standard","monetization":true}}'::jsonb,
					'{"tagline":"Grow your fanbase.","bullets":["Upload up to 10 songs","Standard analytics","Monetization tools"]}'::jsonb
				),
				(
					'artist_pro',
					'artist',
					'Artist Pro',
					15000,
					'month',
					'MWK',
					true,
					true,
					120,
					'{"creator":{"tier":"pro","uploads":{"songs_per_month":"unlimited"},"analytics":"advanced","monetization":true}}'::jsonb,
					'{"tagline":"Unlimited uploads + advanced analytics.","bullets":["Unlimited uploads","Advanced analytics","Priority support"]}'::jsonb
				),
				(
					'dj_starter',
					'dj',
					'DJ Starter',
					0,
					'month',
					'MWK',
					true,
					true,
					210,
					'{"creator":{"tier":"starter","uploads":{"mixes_per_month":4},"analytics":"basic"}}'::jsonb,
					'{"tagline":"Start publishing your mixes.","bullets":["Upload up to 4 mixes","Basic analytics","DJ tools"]}'::jsonb
				),
				(
					'dj_premium',
					'dj',
					'DJ Premium',
					5000,
					'month',
					'MWK',
					true,
					true,
					230,
					'{"creator":{"tier":"premium","uploads":{"mixes_per_month":10},"analytics":"standard","monetization":true}}'::jsonb,
					'{"tagline":"More uploads + monetization.","bullets":["Upload up to 10 mixes","Standard analytics","Monetization tools"]}'::jsonb
				),
				(
					'dj_pro',
					'dj',
					'DJ Pro',
					15000,
					'month',
					'MWK',
					true,
					true,
					220,
					'{"creator":{"tier":"pro","uploads":{"mixes_per_month":"unlimited"},"analytics":"advanced","monetization":true}}'::jsonb,
					'{"tagline":"Unlimited uploads + advanced analytics.","bullets":["Unlimited uploads","Advanced analytics","Priority support"]}'::jsonb
				)
			on conflict (plan_id) do update set
				audience = excluded.audience,
				name = excluded.name,
				price_mwk = excluded.price_mwk,
				billing_interval = excluded.billing_interval,
				currency = excluded.currency,
				active = excluded.active,
				is_active = excluded.is_active,
				sort_order = excluded.sort_order,
				features = excluded.features,
				marketing = excluded.marketing,
				updated_at = now();
		$sql$;
	end if;
end $$;

-- If older migrations seeded artist_* under audience='creator', normalize them.
update public.subscription_plans
set audience = 'artist', updated_at = now()
where plan_id like 'artist_%'
	and (audience is null or audience in ('creator','both','consumer'));

update public.subscription_plans
set audience = 'dj', updated_at = now()
where plan_id like 'dj_%'
	and (audience is null or audience in ('creator','both','consumer'));

