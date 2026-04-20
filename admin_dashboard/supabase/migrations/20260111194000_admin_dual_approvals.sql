-- Dual-approval workflow for high-risk actions (optional usage)

create table if not exists public.admin_dual_approvals (
  id bigserial primary key,
  action_type text not null, -- e.g., 'finance.adjust_coins', 'finance.payout'
  target_type text,
  target_id text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by_admin_id uuid references public.admins (id) on delete set null,
  approved_by_admin_id uuid references public.admins (id) on delete set null,
  requested_at timestamptz not null default now(),
  decided_at timestamptz
);

create index if not exists admin_dual_approvals_status_idx on public.admin_dual_approvals (status);
create index if not exists admin_dual_approvals_action_idx on public.admin_dual_approvals (action_type);

alter table public.admin_dual_approvals enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'admin_dual_approvals' and policyname = 'deny_all_admin_dual_approvals'
  ) then
    create policy deny_all_admin_dual_approvals on public.admin_dual_approvals for all using (false) with check (false);
  end if;
end $$;
