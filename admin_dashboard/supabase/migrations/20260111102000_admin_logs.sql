-- Admin logs (auditing). Service-role bypasses RLS.

create table if not exists public.admin_logs (
  id bigserial primary key,
  admin_email text,
  action text not null,
  target_type text,
  target_id text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_logs_created_at_idx on public.admin_logs (created_at desc);
create index if not exists admin_logs_target_idx on public.admin_logs (target_type, target_id);
create index if not exists admin_logs_admin_email_idx on public.admin_logs (admin_email);

alter table public.admin_logs enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admin_logs'
      and policyname = 'deny_all_admin_logs'
  ) then
    create policy deny_all_admin_logs
      on public.admin_logs
      for all
      using (false)
      with check (false);
  end if;
end $$;
