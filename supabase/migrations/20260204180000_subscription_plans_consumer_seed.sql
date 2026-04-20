-- Seed consumer subscription plans (including weekly tiers) and relax billing_interval constraints.
-- This enables the consumer app to fetch plans from /api/subscriptions/plans and
-- allows PayChangu webhooks to reconcile weekly plan IDs.

create extension if not exists pgcrypto;
-- 1) Ensure billing_interval supports both month + week.
-- Older migrations created a check constraint that only allowed 'month'.
do $$
declare
	c record;
begin
	-- Drop any check constraints that reference subscription_plans.billing_interval.
	for c in (
		select con.conname
		from pg_constraint con
		join pg_class rel on rel.oid = con.conrelid
		join pg_namespace nsp on nsp.oid = rel.relnamespace
		where nsp.nspname = 'public'
			and rel.relname = 'subscription_plans'
			and con.contype = 'c'
			and pg_get_constraintdef(con.oid) ilike '%billing_interval%'
	) loop
		execute format('alter table public.subscription_plans drop constraint if exists %I', c.conname);
	end loop;

	-- If any legacy rows have invalid/NULL billing_interval values, normalize them so
	-- we can safely add the new constraint.
	update public.subscription_plans
	set billing_interval = 'month'
	where billing_interval is null
		or billing_interval not in ('month', 'week');

	-- Re-add a stable constraint name.
	begin
		execute $sql$
			alter table public.subscription_plans
				add constraint subscription_plans_billing_interval_check
				check (billing_interval in ('month','week'));
		$sql$;
	exception when duplicate_object then
		-- already exists
		null;
	end;
end $$;
-- 2) Ensure columns used by the API/UI exist.
alter table public.subscription_plans
	add column if not exists audience text,
	add column if not exists is_active boolean not null default true,
	add column if not exists features jsonb not null default '{}'::jsonb;
alter table public.subscription_plans
	drop constraint if exists subscription_plans_audience_check;
alter table public.subscription_plans
	add constraint subscription_plans_audience_check
	check (audience is null or audience in ('consumer','artist','dj'));
update public.subscription_plans
set audience = 'consumer'
where audience is null;
-- 3) Seed canonical consumer plans.
-- We keep plan_id as the stable identifier (consumer app should never rely on name).
do $$
declare
	has_role boolean;
	has_plan boolean;
	has_price boolean;
	has_currency boolean;
begin
	select exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_plans'
			and column_name = 'role'
	) into has_role;

	select exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_plans'
			and column_name = 'plan'
	) into has_plan;

	select exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_plans'
			and column_name = 'price'
	) into has_price;

	select exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_plans'
			and column_name = 'currency'
	) into has_currency;

	-- Legacy schema: some deployments have extra NOT NULL columns (e.g. role, plan).
	if has_role and has_plan and has_price and has_currency then
		execute $sql$
			with desired as (
				select *
				from (
					values
						(
							'consumer',
							'free',
							'Free',
							0,
							'month',
							1,
							true,
							false,
							'none',
							'basic',
							'limited',
							0.300,
							false,
							'{
								"ads": {"interstitial_every_songs": 3, "interstitial_every_videos": 2},
								"playback": {"skips": {"unlimited": false}, "background_play": false},
								"playlists": {"create": false},
								"downloads": {"enabled": false},
								"quality": {"audio": "low", "video": "low"},
								"battles": {"access": "limited", "priority": "none"},
								"exclusive_content": "none"
							}'::jsonb,
							true,
							'{
								"ads_enabled": true,
								"coins_multiplier": 1,
								"can_participate_battles": false,
								"battle_priority": "none",
								"analytics_level": "basic",
								"content_access": "limited",
								"content_limit_ratio": 0.3,
								"featured_status": false
							}'::jsonb,
							'free',
							'free',
							0,
							'MWK'
						),
						(
							'consumer',
							'premium',
							'Premium',
							5000,
							'month',
							2,
							false,
							true,
							'standard',
							'standard',
							'standard',
							null,
							false,
							'{
								"playback": {"skips": {"unlimited": true}, "background_play": true},
								"downloads": {"enabled": true, "offline_listening": true},
								"playlists": {"create": true},
								"live_streams": {"watch_artists_djs": true, "watch_battles": true},
								"quality": {"audio": "high", "audio_max_kbps": 320, "video": "high"},
								"battles": {"access": "full", "priority": "standard"},
								"billing": {"cancel_anytime": true},
								"exclusive_content": "early_releases"
							}'::jsonb,
							true,
							'{
								"ads_enabled": false,
								"coins_multiplier": 2,
								"can_participate_battles": true,
								"battle_priority": "standard",
								"analytics_level": "standard",
								"content_access": "standard",
								"featured_status": false,
								"battle_limits": {"period": "month", "max": 30}
							}'::jsonb,
							'premium',
							'premium',
							5000,
							'MWK'
						),
						(
							'consumer',
							'premium_weekly',
							'Premium (Weekly)',
							1250,
							'week',
							2,
							false,
							true,
							'standard',
							'standard',
							'standard',
							null,
							false,
							'{
								"playback": {"skips": {"unlimited": true}, "background_play": true},
								"downloads": {"enabled": true, "offline_listening": true},
								"playlists": {"create": true},
								"live_streams": {"watch_artists_djs": true, "watch_battles": true},
								"quality": {"audio": "high", "audio_max_kbps": 320, "video": "high"},
								"battles": {"access": "full", "priority": "standard"},
								"billing": {"cancel_anytime": true},
								"exclusive_content": "early_releases"
							}'::jsonb,
							true,
							'{
								"ads_enabled": false,
								"coins_multiplier": 2,
								"can_participate_battles": true,
								"battle_priority": "standard",
								"analytics_level": "standard",
								"content_access": "standard",
								"featured_status": false,
								"battle_limits": {"period": "week", "max": 8}
							}'::jsonb,
							'premium',
							'premium',
							1250,
							'MWK'
						),
						(
							'consumer',
							'platinum',
							'Platinum',
							8500,
							'month',
							3,
							false,
							true,
							'priority',
							'advanced',
							'exclusive',
							null,
							true,
							'{
								"playback": {"skips": {"unlimited": true}, "background_play": true},
								"downloads": {"enabled": true, "offline_listening": true},
								"playlists": {"create": true, "mix": true},
								"live_streams": {"watch_artists_djs": true, "watch_battles": true},
								"quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1, "video": "high"},
								"ai_dj": {"enabled": true},
								"battles": {"access": "full", "priority": "priority", "replay_anytime": true},
								"billing": {"cancel_anytime": true},
								"coins": {"monthly_free": {"enabled": true, "amount": 200}},
								"badge": {"name": "Platinum"},
								"artist_support": {"enabled": true},
								"exclusive_content": "full",
								"featured_status": true
							}'::jsonb,
							true,
							'{
								"ads_enabled": false,
								"coins_multiplier": 3,
								"can_participate_battles": true,
								"battle_priority": "priority",
								"analytics_level": "advanced",
								"content_access": "exclusive",
								"featured_status": true
							}'::jsonb,
							'platinum',
							'platinum',
							8500,
							'MWK'
						),
						(
							'consumer',
							'platinum_weekly',
							'Platinum (Weekly)',
							2125,
							'week',
							3,
							false,
							true,
							'priority',
							'advanced',
							'exclusive',
							null,
							true,
							'{
								"playback": {"skips": {"unlimited": true}, "background_play": true},
								"downloads": {"enabled": true, "offline_listening": true},
								"playlists": {"create": true, "mix": true},
								"live_streams": {"watch_artists_djs": true, "watch_battles": true},
								"quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1, "video": "high"},
								"ai_dj": {"enabled": true},
								"battles": {"access": "full", "priority": "priority", "replay_anytime": true},
								"billing": {"cancel_anytime": true},
								"coins": {
									"monthly_free": {"enabled": true, "amount": 50},
									"weekly_free": {"enabled": true, "amount": 50}
								},
								"badge": {"name": "Platinum"},
								"artist_support": {"enabled": true},
								"exclusive_content": "full",
								"featured_status": true
							}'::jsonb,
							true,
							'{
								"ads_enabled": false,
								"coins_multiplier": 3,
								"can_participate_battles": true,
								"battle_priority": "priority",
								"analytics_level": "advanced",
								"content_access": "exclusive",
								"featured_status": true
							}'::jsonb,
							'platinum',
							'platinum',
							2125,
							'MWK'
						)
				) as v(
					audience,
					plan_id,
					name,
					price_mwk,
					billing_interval,
					coins_multiplier,
					ads_enabled,
					can_participate_battles,
					battle_priority,
					analytics_level,
					content_access,
					content_limit_ratio,
					featured_status,
					perks,
					is_active,
					features,
					role,
					plan,
					price,
					currency
				)
			),
			upserted as (
				insert into public.subscription_plans (
					audience,
					plan_id,
					name,
					price_mwk,
					billing_interval,
					coins_multiplier,
					ads_enabled,
					can_participate_battles,
					battle_priority,
					analytics_level,
					content_access,
					content_limit_ratio,
					featured_status,
					perks,
					is_active,
					features,
					updated_at,
					role,
					plan,
					price,
					currency
				)
				select
					d.audience,
					d.plan_id,
					d.name,
					d.price_mwk,
					d.billing_interval,
					d.coins_multiplier,
					d.ads_enabled,
					d.can_participate_battles,
					d.battle_priority,
					d.analytics_level,
					d.content_access,
					d.content_limit_ratio,
					d.featured_status,
					d.perks,
					d.is_active,
					d.features,
					now(),
					d.role,
					d.plan,
					d.price,
					d.currency
				from desired d
				on conflict (plan_id) do update
				set
					audience = excluded.audience,
					name = excluded.name,
					price_mwk = excluded.price_mwk,
					billing_interval = excluded.billing_interval,
					coins_multiplier = excluded.coins_multiplier,
					ads_enabled = excluded.ads_enabled,
					can_participate_battles = excluded.can_participate_battles,
					battle_priority = excluded.battle_priority,
					analytics_level = excluded.analytics_level,
					content_access = excluded.content_access,
					content_limit_ratio = excluded.content_limit_ratio,
					featured_status = excluded.featured_status,
					perks = excluded.perks,
					is_active = excluded.is_active,
					features = excluded.features,
					updated_at = excluded.updated_at,
					role = excluded.role,
					plan = excluded.plan,
					price = excluded.price,
					currency = excluded.currency
				returning plan_id
			)
			select
				count(*) as affected
			from upserted;
		$sql$;
	else
		-- Modern schema: seed by plan_id without legacy columns.
		with desired as (
			select *
			from (
				values
					(
						'consumer',
						'free',
						'Free',
						0,
						'month',
						1,
						true,
						false,
						'none',
						'basic',
						'limited',
						0.300,
						false,
						'{
							"ads": {"interstitial_every_songs": 3, "interstitial_every_videos": 2},
							"playback": {"skips": {"unlimited": false}, "background_play": false},
							"playlists": {"create": false},
							"downloads": {"enabled": false},
							"quality": {"audio": "low", "video": "low"},
							"battles": {"access": "limited", "priority": "none"},
							"exclusive_content": "none"
						}'::jsonb,
						true,
						'{
							"ads_enabled": true,
							"coins_multiplier": 1,
							"can_participate_battles": false,
							"battle_priority": "none",
							"analytics_level": "basic",
							"content_access": "limited",
							"content_limit_ratio": 0.3,
							"featured_status": false
						}'::jsonb
					),
					(
						'consumer',
						'premium',
						'Premium',
						5000,
						'month',
						2,
						false,
						true,
						'standard',
						'standard',
						'standard',
						null,
						false,
						'{
							"playback": {"skips": {"unlimited": true}, "background_play": true},
							"downloads": {"enabled": true, "offline_listening": true},
							"playlists": {"create": true},
							"live_streams": {"watch_artists_djs": true, "watch_battles": true},
							"quality": {"audio": "high", "audio_max_kbps": 320, "video": "high"},
							"battles": {"access": "full", "priority": "standard"},
							"billing": {"cancel_anytime": true},
							"exclusive_content": "early_releases"
						}'::jsonb,
						true,
						'{
							"ads_enabled": false,
							"coins_multiplier": 2,
							"can_participate_battles": true,
							"battle_priority": "standard",
							"analytics_level": "standard",
							"content_access": "standard",
							"featured_status": false,
							"battle_limits": {"period": "month", "max": 30}
						}'::jsonb
					),
					(
						'consumer',
						'premium_weekly',
						'Premium (Weekly)',
						1250,
						'week',
						2,
						false,
						true,
						'standard',
						'standard',
						'standard',
						null,
						false,
						'{
							"playback": {"skips": {"unlimited": true}, "background_play": true},
							"downloads": {"enabled": true, "offline_listening": true},
							"playlists": {"create": true},
							"live_streams": {"watch_artists_djs": true, "watch_battles": true},
							"quality": {"audio": "high", "audio_max_kbps": 320, "video": "high"},
							"battles": {"access": "full", "priority": "standard"},
							"billing": {"cancel_anytime": true},
							"exclusive_content": "early_releases"
						}'::jsonb,
						true,
						'{
							"ads_enabled": false,
							"coins_multiplier": 2,
							"can_participate_battles": true,
							"battle_priority": "standard",
							"analytics_level": "standard",
							"content_access": "standard",
							"featured_status": false,
							"battle_limits": {"period": "week", "max": 8}
						}'::jsonb
					),
					(
						'consumer',
						'platinum',
						'Platinum',
						8500,
						'month',
						3,
						false,
						true,
						'priority',
						'advanced',
						'exclusive',
						null,
						true,
						'{
							"playback": {"skips": {"unlimited": true}, "background_play": true},
							"downloads": {"enabled": true, "offline_listening": true},
							"playlists": {"create": true, "mix": true},
							"live_streams": {"watch_artists_djs": true, "watch_battles": true},
							"quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1, "video": "high"},
							"ai_dj": {"enabled": true},
							"battles": {"access": "full", "priority": "priority", "replay_anytime": true},
							"billing": {"cancel_anytime": true},
							"coins": {"monthly_free": {"enabled": true, "amount": 200}},
							"badge": {"name": "Platinum"},
							"artist_support": {"enabled": true},
							"exclusive_content": "full",
							"featured_status": true
						}'::jsonb,
						true,
						'{
							"ads_enabled": false,
							"coins_multiplier": 3,
							"can_participate_battles": true,
							"battle_priority": "priority",
							"analytics_level": "advanced",
							"content_access": "exclusive",
							"featured_status": true
						}'::jsonb
					),
					(
						'consumer',
						'platinum_weekly',
						'Platinum (Weekly)',
						2125,
						'week',
						3,
						false,
						true,
						'priority',
						'advanced',
						'exclusive',
						null,
						true,
						'{
							"playback": {"skips": {"unlimited": true}, "background_play": true},
							"downloads": {"enabled": true, "offline_listening": true},
							"playlists": {"create": true, "mix": true},
							"live_streams": {"watch_artists_djs": true, "watch_battles": true},
							"quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1, "video": "high"},
							"ai_dj": {"enabled": true},
							"battles": {"access": "full", "priority": "priority", "replay_anytime": true},
							"billing": {"cancel_anytime": true},
							"coins": {
								"monthly_free": {"enabled": true, "amount": 50},
								"weekly_free": {"enabled": true, "amount": 50}
							},
							"badge": {"name": "Platinum"},
							"artist_support": {"enabled": true},
							"exclusive_content": "full",
							"featured_status": true
						}'::jsonb,
						true,
						'{
							"ads_enabled": false,
							"coins_multiplier": 3,
							"can_participate_battles": true,
							"battle_priority": "priority",
							"analytics_level": "advanced",
							"content_access": "exclusive",
							"featured_status": true
						}'::jsonb
					)
			) as v(
				audience,
				plan_id,
				name,
				price_mwk,
				billing_interval,
				coins_multiplier,
				ads_enabled,
				can_participate_battles,
				battle_priority,
				analytics_level,
				content_access,
				content_limit_ratio,
				featured_status,
				perks,
				is_active,
				features
			)
		),
		upserted as (
			insert into public.subscription_plans (
				audience,
				plan_id,
				name,
				price_mwk,
				billing_interval,
				coins_multiplier,
				ads_enabled,
				can_participate_battles,
				battle_priority,
				analytics_level,
				content_access,
				content_limit_ratio,
				featured_status,
				perks,
				is_active,
				features,
				updated_at
			)
			select
				d.audience,
				d.plan_id,
				d.name,
				d.price_mwk,
				d.billing_interval,
				d.coins_multiplier,
				d.ads_enabled,
				d.can_participate_battles,
				d.battle_priority,
				d.analytics_level,
				d.content_access,
				d.content_limit_ratio,
				d.featured_status,
				d.perks,
				d.is_active,
				d.features,
				now()
			from desired d
			on conflict (plan_id) do update
			set
				audience = excluded.audience,
				name = excluded.name,
				price_mwk = excluded.price_mwk,
				billing_interval = excluded.billing_interval,
				coins_multiplier = excluded.coins_multiplier,
				ads_enabled = excluded.ads_enabled,
				can_participate_battles = excluded.can_participate_battles,
				battle_priority = excluded.battle_priority,
				analytics_level = excluded.analytics_level,
				content_access = excluded.content_access,
				content_limit_ratio = excluded.content_limit_ratio,
				featured_status = excluded.featured_status,
				perks = excluded.perks,
				is_active = excluded.is_active,
				features = excluded.features,
				updated_at = excluded.updated_at
			returning plan_id
		)
		select
			count(*) as affected
		from upserted;
	end if;
end $$;
-- 4) Seed content access rules for weekly plans (mirror monthly tiers).
-- This is optional but keeps /api/subscriptions/me entitlement resolution consistent.
do $$
declare
	has_plan_rules_table boolean;
	has_rules_in_access_table boolean;
begin
	select exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plan_content_rules'
	) into has_plan_rules_table;

	select exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_content_access'
			and column_name = 'plan_id'
	) into has_rules_in_access_table;

	if has_plan_rules_table then
		execute $sql$
			with desired as (
				select *
				from (
					values
						(
							'premium_weekly',
							jsonb_build_object(
								'content_limit_ratio', 1.0,
								'allowed_categories', jsonb_build_array('all'),
								'videos_access', 'standard',
								'songs_access', 'standard',
								'live_streams', jsonb_build_object(
									'can_watch', true,
									'can_go_live', false,
									'can_join_battles', true,
									'priority_battles', false
								),
								'exclusive_content', jsonb_build_object('level', 'standard')
							)
						),
						(
							'platinum_weekly',
							jsonb_build_object(
								'content_limit_ratio', 1.0,
								'allowed_categories', jsonb_build_array('all'),
								'videos_access', 'vip',
								'songs_access', 'vip',
								'live_streams', jsonb_build_object(
									'can_watch', true,
									'can_go_live', false,
									'can_join_battles', true,
									'priority_battles', true
								),
								'exclusive_content', jsonb_build_object('level', 'vip', 'featured_artist_dj', true)
							)
						)
				) as v(plan_id, rules)
			),
			updated as (
				update public.subscription_plan_content_rules spr
				set
					rules = d.rules,
					updated_at = now()
				from desired d
				where spr.plan_id = d.plan_id
				returning spr.plan_id
			),
			inserted as (
				insert into public.subscription_plan_content_rules (plan_id, rules)
				select d.plan_id, d.rules
				from desired d
				where not exists (
					select 1
					from public.subscription_plan_content_rules spr
					where spr.plan_id = d.plan_id
				)
				returning plan_id
			)
			select
				(select count(*) from updated)
				+ (select count(*) from inserted) as affected;
		$sql$;
	elsif has_rules_in_access_table then
		execute $sql$
			with desired as (
				select *
				from (
					values
						(
							'premium_weekly',
							jsonb_build_object(
								'content_limit_ratio', 1.0,
								'allowed_categories', jsonb_build_array('all'),
								'videos_access', 'standard',
								'songs_access', 'standard',
								'live_streams', jsonb_build_object(
									'can_watch', true,
									'can_go_live', false,
									'can_join_battles', true,
									'priority_battles', false
								),
								'exclusive_content', jsonb_build_object('level', 'standard')
							)
						),
						(
							'platinum_weekly',
							jsonb_build_object(
								'content_limit_ratio', 1.0,
								'allowed_categories', jsonb_build_array('all'),
								'videos_access', 'vip',
								'songs_access', 'vip',
								'live_streams', jsonb_build_object(
									'can_watch', true,
									'can_go_live', false,
									'can_join_battles', true,
									'priority_battles', true
								),
								'exclusive_content', jsonb_build_object('level', 'vip', 'featured_artist_dj', true)
							)
						)
				) as v(plan_id, rules)
			),
			updated as (
				update public.subscription_content_access sca
				set
					rules = d.rules,
					updated_at = now()
				from desired d
				where sca.plan_id = d.plan_id
				returning sca.plan_id
			),
			inserted as (
				insert into public.subscription_content_access (plan_id, rules)
				select d.plan_id, d.rules
				from desired d
				where not exists (
					select 1
					from public.subscription_content_access sca
					where sca.plan_id = d.plan_id
				)
				returning plan_id
			)
			select
				(select count(*) from updated)
				+ (select count(*) from inserted) as affected;
		$sql$;
	else
		raise notice 'Skipping weekly content access rules seed; per-item subscription_content_access schema detected.';
	end if;
end $$;
-- Refresh PostgREST schema cache (helps avoid transient PGRST205 after migrations)
notify pgrst, 'reload schema';
