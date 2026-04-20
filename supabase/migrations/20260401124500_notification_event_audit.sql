-- Audit table for PostgreSQL LISTEN/NOTIFY push fan-out outcomes.

create extension if not exists pgcrypto;

create table if not exists public.notification_event_audit (
  id uuid primary key default gen_random_uuid(),
  event_id text,
  event_type text,
  entity_id text,
  actor_id text,
  country_code text,
  topic text,
  status text not null,
  reason text,
  error text,
  created_at timestamptz not null default now()
);

create index if not exists notification_event_audit_created_at_idx
  on public.notification_event_audit (created_at desc);

create index if not exists notification_event_audit_event_type_idx
  on public.notification_event_audit (event_type);

create index if not exists notification_event_audit_status_idx
  on public.notification_event_audit (status);

alter table public.notification_event_audit enable row level security;

do $$
begin
  begin
    create policy "notification_event_audit service read"
      on public.notification_event_audit
      for select
      to service_role
      using (true);
  exception when duplicate_object then null;
  end;

  begin
    create policy "notification_event_audit service insert"
      on public.notification_event_audit
      for insert
      to service_role
      with check (true);
  exception when duplicate_object then null;
  end;
end $$;

grant select, insert on table public.notification_event_audit to service_role;

select pg_notify('pgrst', 'reload schema');
