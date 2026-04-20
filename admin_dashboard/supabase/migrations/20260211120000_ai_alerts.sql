-- AI Alerts (rule-based detectors)
-- Used by admin AI Security dashboard + Edge Function scanners.

create extension if not exists pgcrypto;

create table if not exists public.ai_alerts (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('coin_abuse', 'fake_stream', 'suspicious_account')),
  reference_id text not null,
  severity text not null check (severity in ('low', 'medium', 'high')),
  message text not null,
  created_at timestamptz not null default now(),
  resolved boolean not null default false,
  resolved_at timestamptz,
  resolved_by_email text
);

create index if not exists ai_alerts_created_at_idx on public.ai_alerts (created_at desc);
create index if not exists ai_alerts_resolved_created_at_idx on public.ai_alerts (resolved, created_at desc);
create index if not exists ai_alerts_type_created_at_idx on public.ai_alerts (type, created_at desc);

alter table public.ai_alerts enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_alerts'
      and policyname = 'deny_all_ai_alerts'
  ) then
    create policy deny_all_ai_alerts
      on public.ai_alerts
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.ai_alerts from anon, authenticated;
grant select, insert, update on table public.ai_alerts to service_role;
