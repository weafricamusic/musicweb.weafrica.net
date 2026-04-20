-- Final canonical statuses:
-- draft, pending_review, approved, rejected, live, completed, cancelled

do $$
declare
	constraint_row record;
begin
	if not exists (
		select 1
		from information_schema.columns
		where table_schema = 'public'
			and table_name = 'events'
			and column_name = 'status'
	) then
		return;
	end if;

	-- Drop any CHECK constraints that mention status (legacy schemas vary)
	for constraint_row in (
		select c.conname
		from pg_constraint c
		join pg_class t on t.oid = c.conrelid
		join pg_namespace n on n.oid = t.relnamespace
		where n.nspname = 'public'
			and t.relname = 'events'
			and c.contype = 'c'
			and pg_get_constraintdef(c.oid) ilike '%status%'
	) loop
		execute format('alter table public.events drop constraint if exists %I', constraint_row.conname);
	end loop;

	-- Normalize legacy / mixed-case values
	update public.events
	set status = 'draft'
	where status is null;

	update public.events
	set status = 'draft'
	where status in ('Draft', 'DRAFT', 'draft');

	update public.events
	set status = 'pending_review'
	where status in (
		'Submitted', 'SUBMITTED', 'submitted',
		'Pending', 'PENDING', 'pending',
		'Pending Review', 'PENDING REVIEW', 'pending review',
		'pending_review', 'PENDING_REVIEW'
	);

	update public.events
	set status = 'approved'
	where status in (
		'Published', 'PUBLISHED', 'published',
		'Approved', 'APPROVED', 'approved'
	);

	update public.events
	set status = 'rejected'
	where status in ('Rejected', 'REJECTED', 'rejected');

	update public.events
	set status = 'live'
	where status in ('Live', 'LIVE', 'live');

	update public.events
	set status = 'completed'
	where status in ('Completed', 'COMPLETED', 'completed');

	update public.events
	set status = 'cancelled'
	where status in (
		'Cancelled', 'CANCELLED', 'cancelled',
		'Canceled', 'CANCELED', 'canceled'
	);

	alter table public.events alter column status set default 'draft'::text;

	alter table public.events
		add constraint events_status_check
		check (
			status = any (
				array[
					'draft'::text,
					'pending_review'::text,
					'approved'::text,
					'rejected'::text,
					'live'::text,
					'completed'::text,
					'cancelled'::text
				]
			)
		);
end
$$;
