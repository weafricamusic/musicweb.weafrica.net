-- Admin audit logs for accountability and compliance.
-- Service-role bypasses RLS; normal clients are denied by default.

create table if not exists public.admin_audit_logs (
  id bigserial primary key,
  admin_id text,
  admin_email text,
  action text not null,
  target_type text,
  target_id text,
  before_state jsonb,
  after_state jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_logs_created_at_idx on public.admin_audit_logs (created_at desc);
create index if not exists admin_audit_logs_admin_idx on public.admin_audit_logs (admin_id, admin_email);
create index if not exists admin_audit_logs_target_idx on public.admin_audit_logs (target_type, target_id);

alter table public.admin_audit_logs enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admin_audit_logs'
      and policyname = 'deny_all_admin_audit_logs'
  ) then
    create policy deny_all_admin_audit_logs
      on public.admin_audit_logs
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Optional RPC for convenience (service role can bypass RLS anyway)
create or replace function public.log_admin_action(
  p_admin_id text,
  p_admin_email text,
  p_action text,
  p_target_type text,
  p_target_id text,
  p_before_state jsonb,
  p_after_state jsonb,
  p_ip_address text,
  p_user_agent text
) returns void
language sql
security definer
as $$
  insert into public.admin_audit_logs (
    admin_id, admin_email, action, target_type, target_id,
    before_state, after_state, ip_address, user_agent
  ) values (
    p_admin_id, p_admin_email, p_action, p_target_type, p_target_id,
    p_before_state, p_after_state, p_ip_address, p_user_agent
  );
$$;
