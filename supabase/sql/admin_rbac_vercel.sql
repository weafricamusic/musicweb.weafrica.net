-- WeAfrica Music — Admin RBAC + Control SQL (Vercel-friendly)
--
-- Use this when your admin web app (on Vercel) runs privileged actions server-side
-- using the Supabase `service_role` key (DO NOT expose it to the browser).
--
-- Safe to run multiple times (idempotent where practical).

-- ============================================================================
-- 0) Extensions
-- ============================================================================
create extension if not exists pgcrypto;

-- ============================================================================
-- 1) Admin RBAC (accounts + permissions)
-- ============================================================================

-- Admin accounts table (email-based; optional Firebase uid)
create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  uid text,
  email text not null unique,
  role text not null check (role in ('super_admin','operations_admin','finance_admin','support_admin')),
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);

create index if not exists admins_email_idx on public.admins (email);
create index if not exists admins_role_idx on public.admins (role);

alter table public.admins enable row level security;

-- Deny all for anon/authenticated; allow service_role bypass (server-only).
-- (Policies are idempotent via pg_policies check.)
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admins'
      and policyname = 'deny_all_admins'
  ) then
    create policy deny_all_admins
      on public.admins
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Role permissions matrix
create table if not exists public.role_permissions (
  role text primary key,
  can_manage_users boolean not null default false,
  can_manage_artists boolean not null default false,
  can_manage_djs boolean not null default false,
  can_manage_finance boolean not null default false,
  can_stop_streams boolean not null default false,
  can_manage_admins boolean not null default false,
  can_view_logs boolean not null default true
);

alter table public.role_permissions enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'role_permissions'
      and policyname = 'deny_all_role_permissions'
  ) then
    create policy deny_all_role_permissions
      on public.role_permissions
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Seed role permissions (upsert)
insert into public.role_permissions as rp (
  role,
  can_manage_users,
  can_manage_artists,
  can_manage_djs,
  can_manage_finance,
  can_stop_streams,
  can_manage_admins,
  can_view_logs
) values
  ('super_admin',      true,  true,  true,  true,  true,  true,  true),
  ('operations_admin', true,  true,  true,  false, true,  false, true),
  ('finance_admin',    false, false, false, true,  false, false, true),
  ('support_admin',    false, false, false, false, false, false, true)
on conflict (role) do update set
  can_manage_users  = excluded.can_manage_users,
  can_manage_artists = excluded.can_manage_artists,
  can_manage_djs     = excluded.can_manage_djs,
  can_manage_finance = excluded.can_manage_finance,
  can_stop_streams   = excluded.can_stop_streams,
  can_manage_admins  = excluded.can_manage_admins,
  can_view_logs      = excluded.can_view_logs;

-- View used by server code to resolve permissions fast
create or replace view public.admins_with_permissions as
select
  a.id,
  a.uid,
  a.email,
  a.role,
  a.status,
  a.created_at,
  a.last_login_at,
  p.can_manage_users,
  p.can_manage_artists,
  p.can_manage_djs,
  p.can_manage_finance,
  p.can_stop_streams,
  p.can_manage_admins,
  p.can_view_logs
from public.admins a
join public.role_permissions p on p.role = a.role;

-- Refresh PostgREST schema cache
notify pgrst, 'reload schema';

-- ============================================================================
-- 2) Admin control tables (settings + announcements + flags)
-- ============================================================================

create table if not exists public.admin_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  status text not null default 'queued',
  created_at timestamptz not null default now()
);
create index if not exists admin_announcements_created_at_idx
  on public.admin_announcements (created_at desc);

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

-- Lock these tables behind service_role by default.
-- (You can add policies later if you want authenticated admin clients to read/write.)

do $$
begin
  alter table public.admin_settings enable row level security;
  alter table public.admin_announcements enable row level security;
  alter table public.fraud_flags enable row level security;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='admin_settings' and policyname='deny_all_admin_settings') then
    create policy deny_all_admin_settings on public.admin_settings for all using (false) with check (false);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='admin_announcements' and policyname='deny_all_admin_announcements') then
    create policy deny_all_admin_announcements on public.admin_announcements for all using (false) with check (false);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='fraud_flags' and policyname='deny_all_fraud_flags') then
    create policy deny_all_fraud_flags on public.fraud_flags for all using (false) with check (false);
  end if;
end $$;

-- ============================================================================
-- 3) Admin audit / logs (optional but useful)
-- ============================================================================

create table if not exists public.admin_activity (
  id bigserial primary key,
  actor_uid text,
  action text not null,
  entity text,
  entity_id text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_activity_created_at_idx on public.admin_activity (created_at desc);
create index if not exists admin_activity_entity_idx on public.admin_activity (entity, entity_id);
create index if not exists admin_activity_actor_uid_idx on public.admin_activity (actor_uid);

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

-- Deny all for normal clients; service_role bypasses RLS.

do $$
begin
  alter table public.admin_activity enable row level security;
  alter table public.admin_logs enable row level security;
  alter table public.admin_audit_logs enable row level security;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='admin_activity' and policyname='deny_all_admin_activity') then
    create policy deny_all_admin_activity on public.admin_activity for all using (false) with check (false);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='admin_logs' and policyname='deny_all_admin_logs') then
    create policy deny_all_admin_logs on public.admin_logs for all using (false) with check (false);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='admin_audit_logs' and policyname='deny_all_admin_audit_logs') then
    create policy deny_all_admin_audit_logs on public.admin_audit_logs for all using (false) with check (false);
  end if;
end $$;

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
set search_path = public
as $$
  insert into public.admin_audit_logs (
    admin_id, admin_email, action, target_type, target_id,
    before_state, after_state, ip_address, user_agent
  ) values (
    p_admin_id, p_admin_email, p_action, p_target_type, p_target_id,
    p_before_state, p_after_state, p_ip_address, p_user_agent
  );
$$;

-- ============================================================================
-- 4) OPTIONAL: RLS admin override (ONLY if you do NOT use service_role)
-- ============================================================================
-- If your Vercel admin app uses Supabase Auth + anon key (RLS enforced),
-- you can allow admin users to update controlled tables by adding policies.
--
-- This helper checks the JWT email claim against `public.admins`.
-- It is SECURITY DEFINER so it can read `public.admins` even though that table
-- denies access under RLS for normal roles.
--
-- NOTE: If you are not using Supabase Auth (e.g., Firebase-only), this section
-- won't work as-is because the JWT email claim won't be present.

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admins a
    where a.status = 'active'
      and lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

grant execute on function public.is_platform_admin() to anon, authenticated;

-- Example policies (uncomment if needed):
-- do $$ begin
--   create policy "Admin manage artists" on public.artists
--     for all to authenticated
--     using (public.is_platform_admin())
--     with check (public.is_platform_admin());
-- exception when duplicate_object then null; end $$;
--
-- do $$ begin
--   create policy "Admin manage djs" on public.djs
--     for all to authenticated
--     using (public.is_platform_admin())
--     with check (public.is_platform_admin());
-- exception when duplicate_object then null; end $$;
--
-- do $$ begin
--   create policy "Admin manage songs" on public.songs
--     for all to authenticated
--     using (public.is_platform_admin())
--     with check (public.is_platform_admin());
-- exception when duplicate_object then null; end $$;
--
-- do $$ begin
--   create policy "Admin manage videos" on public.videos
--     for all to authenticated
--     using (public.is_platform_admin())
--     with check (public.is_platform_admin());
-- exception when duplicate_object then null; end $$;

-- Refresh PostgREST schema cache (safe)
notify pgrst, 'reload schema';
