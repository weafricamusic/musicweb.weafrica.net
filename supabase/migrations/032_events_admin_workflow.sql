-- Events admin workflow additions (Pending approvals + admin notes)
--
-- Idempotent, safe on existing installations.

create extension if not exists pgcrypto;
do $$
begin
  if to_regclass('public.events') is not null then
    execute 'alter table public.events add column if not exists admin_notes text';
    execute 'alter table public.events add column if not exists reviewed_by text';
    execute 'alter table public.events add column if not exists reviewed_at timestamptz';

    -- Relax/expand status check to support moderation workflow.
    begin
      execute 'alter table public.events drop constraint if exists events_status_check';
    exception when undefined_object then
      null;
    end;

    begin
      execute $sql$
        alter table public.events
        add constraint events_status_check
        check (lower(status) in ('draft','submitted','published','rejected','completed'))
      $sql$;
    exception when others then
      -- If existing data violates the constraint, keep the table usable.
      null;
    end;
  end if;
end
$$;
