-- Two-sided subscription plan catalog: Listener (consumer) + Creator tiers.
--
-- Goals:
-- - Keep the Edge API contract stable: subscription_plans supports
--   plan_id,audience,name,price_mwk,billing_interval,currency,active,features,marketing,sort_order
-- - Bridge drift across older schemas that also include: role, plan, price, is_active
-- - Seed/update the plan rows used by the app paywall.

create extension if not exists pgcrypto;

-- 1) Ensure core columns exist (idempotent).
alter table if exists public.subscription_plans
	add column if not exists plan_id text,
	add column if not exists audience text,
	add column if not exists name text,
	add column if not exists price_mwk integer,
	add column if not exists billing_interval text,
	add column if not exists currency text,
	add column if not exists active boolean,
	add column if not exists sort_order integer,
	add column if not exists features jsonb,
	add column if not exists marketing jsonb,
	add column if not exists updated_at timestamptz;

-- Backfill safe defaults.
do $$
begin
	update public.subscription_plans
	set
		currency = coalesce(nullif(trim(currency), ''), 'MWK'),
		billing_interval = coalesce(nullif(trim(billing_interval), ''), 'month')
	where currency is null
		or billing_interval is null
		or trim(currency) = ''
		or trim(billing_interval) = '';

	update public.subscription_plans
	set price_mwk = coalesce(price_mwk, 0)
	where price_mwk is null;

	update public.subscription_plans
	set sort_order = coalesce(sort_order, 0)
	where sort_order is null;

	update public.subscription_plans
	set audience = 'consumer'
	where audience is null or trim(audience) = '';
exception
	when undefined_table then
		raise notice 'subscription_plans missing; skipping defaults backfill.';
end $$;

-- 2) Relax audience constraints across drifted deployments.
-- Some migrations used ('consumer','artist','dj'), others used ('consumer','creator','both').
-- We allow the superset and let the API interpret it.
do $$
declare
	c record;
begin
	if not exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	) then
		raise notice 'subscription_plans missing; skipping audience constraint alignment.';
		return;
	end if;

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
	exception
		when duplicate_object then
			null;
	end;
end $$;

-- 2.5) Remove legacy plan_id whitelist constraint(s).
-- Some deployments were created with: check (plan_id in ('free','premium','platinum'))
-- which prevents adding new plan IDs like 'family' or 'artist_pro'.
alter table if exists public.subscription_plans
	drop constraint if exists subscription_plans_plan_id_check;

do $$
declare
	c record;
begin
	if not exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	) then
		raise notice 'subscription_plans missing; skipping plan_id whitelist constraint removal.';
		return;
	end if;

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

-- 3) Keep active flags compatible (some DBs use is_active instead of active).
alter table if exists public.subscription_plans
	add column if not exists is_active boolean;

do $$
begin
	if not exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	) then
		raise notice 'subscription_plans missing; skipping active/is_active sync.';
		return;
	end if;

	-- Canonicalize: prefer `active` when present, else fall back to `is_active`, else true.
	update public.subscription_plans
	set
		active = case
			when active is not null then active
			when is_active is not null then is_active
			else true
		end,
		is_active = case
			when active is not null then active
			when is_active is not null then is_active
			else true
		end,
		updated_at = now()
	where active is null
		or is_active is null
		or active is distinct from is_active;
end $$;

create or replace function public._subscription_plans_coalesce_active()
returns trigger
language plpgsql
as $$
declare
	v_active boolean;
begin
	-- Prefer whichever column was explicitly updated; keep both columns identical.
	if TG_OP = 'INSERT' then
		v_active := coalesce(new.active, new.is_active, true);
	else
		if new.is_active is distinct from old.is_active and new.active is not distinct from old.active then
			v_active := coalesce(new.is_active, new.active, true);
		else
			v_active := coalesce(new.active, new.is_active, true);
		end if;
	end if;

	new.active := v_active;
	new.is_active := v_active;
	new.updated_at := now();
	return new;
end;
$$;

-- NOTE: subscription_plans_set_updated_at trigger may also exist; this trigger only keeps flags in sync.
do $$
begin
	if not exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	) then
		return;
	end if;

	drop trigger if exists trg_subscription_plans_coalesce_active on public.subscription_plans;
	create trigger trg_subscription_plans_coalesce_active
	before insert or update of active, is_active
	on public.subscription_plans
	for each row
	execute function public._subscription_plans_coalesce_active();
end $$;

-- 4) Seed/update plan rows.
-- NOTE: We keep legacy plan_ids ('premium','platinum') for compatibility with existing client gating,
-- but update their display names + pricing to match the new product.

do $$
declare
	has_role boolean;
	has_plan boolean;
	has_price boolean;
	has_currency boolean;
begin
	if not exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	) then
		raise notice 'subscription_plans missing; skipping paywall seed.';
		return;
	end if;

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
					'free',
					'consumer',
					'Free',
					0,
					'month',
					'MWK',
					true,
					true,
					0,
					'{"perks":{"ads":{"enabled":true,"interstitial_every_songs":3},"downloads":{"enabled":false},"playback":{"background_play":false}}}'::jsonb,
					'{"tagline":"Listen for free","bullets":["Ad-supported listening"]}'::jsonb,
					'free',
					'free',
					0
				),
				(
					'premium',
					'consumer',
					'WeAfrica Plus',
					3000,
					'month',
					'MWK',
					true,
					true,
					10,
					'{"perks":{"ads":{"enabled":false,"interstitial_every_songs":0},"downloads":{"enabled":true},"audio":{"max_kbps":320},"playback":{"background_play":true},"playlists":{"create":true}}}'::jsonb,
					'{"tagline":"Ad‑free + offline listening.","bullets":["No ads","Download to listen offline","High quality audio (up to 320 kbps)","Unlimited skips","Create playlists"]}'::jsonb,
					'premium',
					'premium',
					3000
				),
				(
					'platinum',
					'consumer',
					'WeAfrica Superfan',
					6000,
					'month',
					'MWK',
					true,
					true,
					20,
					'{"perks":{"ads":{"enabled":false,"interstitial_every_songs":0},"downloads":{"enabled":true},"audio":{"max_kbps":320,"tier":"24bit"},"playback":{"background_play":true},"content":{"access":"exclusive"}}}'::jsonb,
					'{"tagline":"Studio quality + exclusive drops.","bullets":["Everything in Plus","Audio up to 24‑bit / 44.1kHz","Early releases","Exclusive content","Priority access in live battles"]}'::jsonb,
					'platinum',
					'platinum',
					6000
				),
				(
					'family',
					'consumer',
					'WeAfrica Family',
					10000,
					'month',
					'MWK',
					true,
					true,
					30,
					'{"perks":{"ads":{"enabled":false,"interstitial_every_songs":0},"downloads":{"enabled":true},"audio":{"tier":"24bit"},"family":{"accounts":4}}}'::jsonb,
					'{"tagline":"Share with the whole family.","bullets":["All Superfan benefits","Up to 4 accounts","One monthly payment"]}'::jsonb,
					'family',
					'family',
					10000
				),
				(
					'artist_premium',
					'creator',
					'Artist Premium',
					5000,
					'month',
					'MWK',
					true,
					true,
					10,
					'{"creator":{"uploads":{"songs_per_month":5},"analytics":"basic","distribution":true}}'::jsonb,
					'{"tagline":"Start distributing your music.","bullets":["Upload up to 5 songs","Basic analytics","Creator tools","Cancel anytime"]}'::jsonb,
					'artist_premium',
					'artist_premium',
					5000
				),
				(
					'artist_pro',
					'creator',
					'Artist Pro',
					15000,
					'month',
					'MWK',
					true,
					true,
					20,
					'{"creator":{"uploads":{"songs_per_month":"unlimited"},"analytics":"advanced","distribution":true,"monetization":true}}'::jsonb,
					'{"tagline":"Unlimited uploads + advanced analytics.","bullets":["Unlimited uploads","Advanced analytics","Digital sales + monetization","Priority support"]}'::jsonb,
					'artist_pro',
					'artist_pro',
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
					'free',
					'consumer',
					'Free',
					0,
					'month',
					'MWK',
					true,
					true,
					0,
					'{"perks":{"ads":{"enabled":true,"interstitial_every_songs":3},"downloads":{"enabled":false},"playback":{"background_play":false}}}'::jsonb,
					'{"tagline":"Listen for free","bullets":["Ad-supported listening"]}'::jsonb
				),
				(
					'premium',
					'consumer',
					'WeAfrica Plus',
					3000,
					'month',
					'MWK',
					true,
					true,
					10,
					'{"perks":{"ads":{"enabled":false,"interstitial_every_songs":0},"downloads":{"enabled":true},"audio":{"max_kbps":320},"playback":{"background_play":true},"playlists":{"create":true}}}'::jsonb,
					'{"tagline":"Ad‑free + offline listening.","bullets":["No ads","Download to listen offline","High quality audio (up to 320 kbps)","Unlimited skips","Create playlists"]}'::jsonb
				),
				(
					'platinum',
					'consumer',
					'WeAfrica Superfan',
					6000,
					'month',
					'MWK',
					true,
					true,
					20,
					'{"perks":{"ads":{"enabled":false,"interstitial_every_songs":0},"downloads":{"enabled":true},"audio":{"max_kbps":320,"tier":"24bit"},"playback":{"background_play":true},"content":{"access":"exclusive"}}}'::jsonb,
					'{"tagline":"Studio quality + exclusive drops.","bullets":["Everything in Plus","Audio up to 24‑bit / 44.1kHz","Early releases","Exclusive content","Priority access in live battles"]}'::jsonb
				),
				(
					'family',
					'consumer',
					'WeAfrica Family',
					10000,
					'month',
					'MWK',
					true,
					true,
					30,
					'{"perks":{"ads":{"enabled":false,"interstitial_every_songs":0},"downloads":{"enabled":true},"audio":{"tier":"24bit"},"family":{"accounts":4}}}'::jsonb,
					'{"tagline":"Share with the whole family.","bullets":["All Superfan benefits","Up to 4 accounts","One monthly payment"]}'::jsonb
				),
				(
					'artist_premium',
					'creator',
					'Artist Premium',
					5000,
					'month',
					'MWK',
					true,
					true,
					10,
					'{"creator":{"uploads":{"songs_per_month":5},"analytics":"basic","distribution":true}}'::jsonb,
					'{"tagline":"Start distributing your music.","bullets":["Upload up to 5 songs","Basic analytics","Creator tools","Cancel anytime"]}'::jsonb
				),
				(
					'artist_pro',
					'creator',
					'Artist Pro',
					15000,
					'month',
					'MWK',
					true,
					true,
					20,
					'{"creator":{"uploads":{"songs_per_month":"unlimited"},"analytics":"advanced","distribution":true,"monetization":true}}'::jsonb,
					'{"tagline":"Unlimited uploads + advanced analytics.","bullets":["Unlimited uploads","Advanced analytics","Digital sales + monetization","Priority support"]}'::jsonb
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

-- Helpful indexes for the API.
create index if not exists subscription_plans_active_idx on public.subscription_plans(active);
create index if not exists subscription_plans_audience_idx on public.subscription_plans(audience);
create index if not exists subscription_plans_sort_order_idx on public.subscription_plans(sort_order);

-- Hint PostgREST to refresh its schema cache after altering subscription_plans.
notify pgrst, 'reload schema';
