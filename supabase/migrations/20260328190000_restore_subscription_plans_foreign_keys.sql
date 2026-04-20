-- Restore foreign keys that may have been removed if `subscription_plans` was ever dropped/recreated.
--
-- This is defensive: it only adds constraints when the target tables/columns exist and
-- the constraints are missing. Constraints are added as NOT VALID to avoid failing on
-- legacy inconsistent data, then validated best-effort.

create extension if not exists pgcrypto;

-- user_subscriptions.plan_id -> subscription_plans.plan_id
do $$
begin
	if exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	)
	and exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'user_subscriptions'
	)
	and exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'user_subscriptions'
			and column_name = 'plan_id'
	)
	and not exists (
		select 1
		from information_schema.table_constraints
		where table_schema = 'public'
			and table_name = 'user_subscriptions'
			and constraint_type = 'FOREIGN KEY'
			and constraint_name = 'user_subscriptions_plan_id_fkey'
	) then
		begin
			alter table public.user_subscriptions
				add constraint user_subscriptions_plan_id_fkey
				foreign key (plan_id)
				references public.subscription_plans (plan_id)
				not valid;
		exception when duplicate_object then
			null;
		end;

		begin
			alter table public.user_subscriptions
				validate constraint user_subscriptions_plan_id_fkey;
		exception when others then
			raise notice 'Skipping validation for user_subscriptions_plan_id_fkey: %', sqlerrm;
		end;
	end if;
end $$;

-- subscription_payments.plan_id -> subscription_plans.plan_id (on delete set null)
do $$
begin
	if exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	)
	and exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_payments'
	)
	and exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_payments'
			and column_name = 'plan_id'
	)
	and not exists (
		select 1
		from information_schema.table_constraints
		where table_schema = 'public'
			and table_name = 'subscription_payments'
			and constraint_type = 'FOREIGN KEY'
			and constraint_name = 'subscription_payments_plan_id_fkey'
	) then
		begin
			alter table public.subscription_payments
				add constraint subscription_payments_plan_id_fkey
				foreign key (plan_id)
				references public.subscription_plans (plan_id)
				on delete set null
				not valid;
		exception when duplicate_object then
			null;
		end;

		begin
			alter table public.subscription_payments
				validate constraint subscription_payments_plan_id_fkey;
		exception when others then
			raise notice 'Skipping validation for subscription_payments_plan_id_fkey: %', sqlerrm;
		end;
	end if;
end $$;

-- subscription_promotions.target_plan_id -> subscription_plans.plan_id (on delete set null)
do $$
begin
	if exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	)
	and exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_promotions'
	)
	and exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_promotions'
			and column_name = 'target_plan_id'
	)
	and not exists (
		select 1
		from information_schema.table_constraints
		where table_schema = 'public'
			and table_name = 'subscription_promotions'
			and constraint_type = 'FOREIGN KEY'
			and constraint_name = 'subscription_promotions_target_plan_id_fkey'
	) then
		begin
			alter table public.subscription_promotions
				add constraint subscription_promotions_target_plan_id_fkey
				foreign key (target_plan_id)
				references public.subscription_plans (plan_id)
				on delete set null
				not valid;
		exception when duplicate_object then
			null;
		end;

		begin
			alter table public.subscription_promotions
				validate constraint subscription_promotions_target_plan_id_fkey;
		exception when others then
			raise notice 'Skipping validation for subscription_promotions_target_plan_id_fkey: %', sqlerrm;
		end;
	end if;
end $$;

-- paychangu_payments.plan_id -> subscription_plans.plan_id (on update cascade)
do $$
begin
	if exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	)
	and exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'paychangu_payments'
	)
	and exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'paychangu_payments'
			and column_name = 'plan_id'
	)
	and not exists (
		select 1
		from information_schema.table_constraints
		where table_schema = 'public'
			and table_name = 'paychangu_payments'
			and constraint_type = 'FOREIGN KEY'
			and constraint_name = 'paychangu_payments_plan_id_fkey'
	) then
		begin
			alter table public.paychangu_payments
				add constraint paychangu_payments_plan_id_fkey
				foreign key (plan_id)
				references public.subscription_plans (plan_id)
				on update cascade
				not valid;
		exception when duplicate_object then
			null;
		end;

		begin
			alter table public.paychangu_payments
				validate constraint paychangu_payments_plan_id_fkey;
		exception when others then
			raise notice 'Skipping validation for paychangu_payments_plan_id_fkey: %', sqlerrm;
		end;
	end if;
end $$;

-- subscription_plan_content_rules.plan_id -> subscription_plans.plan_id
-- Note: historically this table was renamed from subscription_content_access, so we preserve
-- the legacy constraint name when recreating it.
do $$
begin
	if exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plans'
	)
	and exists (
		select 1
		from information_schema.tables
		where table_schema = 'public'
			and table_name = 'subscription_plan_content_rules'
	)
	and exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'subscription_plan_content_rules'
			and column_name = 'plan_id'
	)
	and not exists (
		select 1
		from information_schema.table_constraints
		where table_schema = 'public'
			and table_name = 'subscription_plan_content_rules'
			and constraint_type = 'FOREIGN KEY'
			and constraint_name = 'subscription_content_access_plan_id_fkey'
	) then
		begin
			alter table public.subscription_plan_content_rules
				add constraint subscription_content_access_plan_id_fkey
				foreign key (plan_id)
				references public.subscription_plans (plan_id)
				not valid;
		exception when duplicate_object then
			null;
		end;

		begin
			alter table public.subscription_plan_content_rules
				validate constraint subscription_content_access_plan_id_fkey;
		exception when others then
			raise notice 'Skipping validation for subscription_content_access_plan_id_fkey: %', sqlerrm;
		end;
	end if;
end $$;
