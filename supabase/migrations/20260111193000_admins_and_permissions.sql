-- Admins and Role Permissions for WeAfrica RBAC

-- Needed for gen_random_uuid() on some Postgres setups
create extension if not exists pgcrypto;
-- 1) Core admin accounts table (Firebase email + status)
create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  uid text, -- Firebase UID if available
  email text not null unique,
  role text not null check (role in ('super_admin','operations_admin','finance_admin','support_admin')),
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);
create index if not exists admins_email_idx on public.admins (email);
create index if not exists admins_role_idx on public.admins (role);
alter table public.admins enable row level security;
-- Deny all by default. Server uses service role.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'admins'
      and policyname = 'deny_all_admins'
  ) then
    create policy deny_all_admins on public.admins for all using (false) with check (false);
  end if;
end $$;
-- 2) Role permissions matrix. Booleans keep it simple and fast.
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
-- Deny all by default; reads happen via service role.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'role_permissions'
      and policyname = 'deny_all_role_permissions'
  ) then
    create policy deny_all_role_permissions on public.role_permissions for all using (false) with check (false);
  end if;
end $$;
-- 3) Seed role permissions (upsert for idempotency)
insert into public.role_permissions as rp (
  role, can_manage_users, can_manage_artists, can_manage_djs, can_manage_finance, can_stop_streams, can_manage_admins, can_view_logs
) values
  -- Super Admin: full power
  ('super_admin', true, true, true, true, true, true, true),
  -- Operations Admin: manage artists/DJs, streams, moderation
  ('operations_admin', true, true, true, false, true, false, true),
  -- Finance Admin: finance only
  ('finance_admin', false, false, false, true, false, false, true),
  -- Support/Moderation: view-only
  ('support_admin', false, false, false, false, false, false, true)
  on conflict (role) do update set
    can_manage_users = excluded.can_manage_users,
    can_manage_artists = excluded.can_manage_artists,
    can_manage_djs = excluded.can_manage_djs,
    can_manage_finance = excluded.can_manage_finance,
    can_stop_streams = excluded.can_stop_streams,
    can_manage_admins = excluded.can_manage_admins,
    can_view_logs = excluded.can_view_logs;
-- 4) Convenience view joining admins with permissions
drop view if exists public.admins_with_permissions;
create view public.admins_with_permissions as
select a.id,
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
-- Refresh PostgREST schema cache (fixes "Could not find table ... in schema cache")
notify pgrst, 'reload schema';
