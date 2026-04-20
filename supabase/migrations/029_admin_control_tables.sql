-- Admin control tables used by the in-app Admin Dashboard.
--
-- IMPORTANT:
-- This project commonly uses Firebase Auth UIDs (text) across the DB.
-- If you want production-safe admin access, you must authenticate requests to Supabase
-- such that `auth.uid()` becomes meaningful (e.g., Supabase Auth / verified JWT).
-- Only then should you enable RLS and policies on these tables.

create extension if not exists pgcrypto;
-- Expand user_roles to support multi-level admin roles and activation.
alter table if exists public.user_roles
  add column if not exists is_active boolean not null default true;
-- Replace the role check constraint to include admin levels.
do $$
declare
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.user_roles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%role%in%'
  loop
    execute format('alter table public.user_roles drop constraint if exists %I', c.conname);
  end loop;

  execute $ddl$
    alter table public.user_roles
      add constraint user_roles_role_check
      check (role in ('consumer','artist','dj','admin','super_admin','finance_admin','moderator'))
  $ddl$;
end $$;
-- Admin settings (key-value) for platform-level tuning.
create table if not exists public.admin_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
-- Admin announcements (in-app / push hooks can be added later).
create table if not exists public.admin_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  status text not null default 'queued',
  created_at timestamptz not null default now()
);
create index if not exists admin_announcements_created_at_idx on public.admin_announcements (created_at desc);
-- Admin audit log (best-effort inserts from the app).
create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_log_created_at_idx on public.admin_audit_log (created_at desc);
-- Fraud flags (server-side detection can populate this table).
create table if not exists public.fraud_flags (
  id uuid primary key default gen_random_uuid(),
  user_id text,
  kind text not null,
  risk_score numeric not null default 0,
  status text not null default 'open',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists fraud_flags_status_idx on public.fraud_flags (status);
create index if not exists fraud_flags_created_at_idx on public.fraud_flags (created_at desc);
-- OPTIONAL (recommended once Supabase Auth is in place):
-- alter table public.admin_settings enable row level security;
-- alter table public.admin_announcements enable row level security;
-- alter table public.admin_audit_log enable row level security;
-- alter table public.fraud_flags enable row level security;
--
-- create policy "admin only" on public.admin_settings for all
--   using (exists (select 1 from public.user_roles ur where ur.user_id = auth.uid()::text and ur.role in ('admin','super_admin','finance_admin','moderator') and ur.is_active = true));
--
-- Apply similar policies to admin_announcements, admin_audit_log, fraud_flags.;
