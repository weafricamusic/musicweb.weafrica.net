-- Add admin_role and country columns to admin_audit_logs

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='admin_audit_logs' and column_name='admin_role'
  ) then
    alter table public.admin_audit_logs add column admin_role text;
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='admin_audit_logs' and column_name='country'
  ) then
    alter table public.admin_audit_logs add column country text;
    create index if not exists admin_audit_logs_country_idx on public.admin_audit_logs (country);
  end if;
end $$;
