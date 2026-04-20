-- Admin security layer: profile admin flags + role permissions.
--
-- Notes:
-- - `profiles.id` is expected to be the Firebase UID (TEXT).
-- - This migration is idempotent and safe to re-run.

create extension if not exists pgcrypto;

-- 1) Add admin fields to profiles.
alter table public.profiles
  add column if not exists is_admin boolean not null default false,
  add column if not exists admin_role text not null default 'viewer',
  -- Moderation/account state fields (used by admin actions).
  add column if not exists status text not null default 'active',
  add column if not exists suspended_at timestamptz,
  add column if not exists banned_at timestamptz,
  add column if not exists ban_reason text,
  add column if not exists banned_by text,
  add column if not exists promoted_at timestamptz,
  add column if not exists promoted_by text;

do $$
begin
  begin
    alter table public.profiles
      drop constraint if exists profiles_admin_role_check;
  exception
    when undefined_object then null;
  end;

  alter table public.profiles
    add constraint profiles_admin_role_check
    check (admin_role in ('viewer', 'moderator', 'admin', 'super_admin'));
exception
  when duplicate_object then null;
end $$;

do $$
begin
  begin
    alter table public.profiles
      drop constraint if exists profiles_status_check;
  exception
    when undefined_object then null;
  end;

  alter table public.profiles
    add constraint profiles_status_check
    check (status in ('active', 'suspended', 'banned'));
exception
  when duplicate_object then null;
end $$;

-- 2) Admin roles table for fine-grained permissions.
-- IMPORTANT:
-- This repo already has an older migration that creates `public.admin_roles` as a *user-role assignment* table
-- (columns like `user_id`, `role`). To avoid breaking that, we store role permission definitions in a separate table.

create table if not exists public.admin_role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_name text not null unique,
  permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_role_permissions enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admin_role_permissions'
      and policyname = 'deny_all_admin_role_permissions'
  ) then
    create policy deny_all_admin_role_permissions
      on public.admin_role_permissions
      for all
      using (false)
      with check (false);
  end if;
end $$;

revoke all on table public.admin_role_permissions from anon, authenticated;

-- If this migration was previously run and failed mid-way, it may have revoked access on the legacy
-- `public.admin_roles` assignment table. Restore authenticated SELECT so existing admin UI flows remain usable.
do $$
begin
  if to_regclass('public.admin_roles') is not null
     and exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'admin_roles'
         and column_name = 'user_id'
     ) then
    grant select on table public.admin_roles to authenticated;
  end if;
exception
  when undefined_table then null;
  when insufficient_privilege then null;
end $$;

-- 3) Seed default roles.
insert into public.admin_role_permissions (role_name, permissions)
values
  ('viewer', '{"dashboard": true}'::jsonb),
  ('moderator', '{"dashboard": true, "moderate": true, "users_view": true}'::jsonb),
  ('admin', '{"dashboard": true, "moderate": true, "users": true, "finance": true, "content": true, "admin": true}'::jsonb),
  ('super_admin', '{"all": true}'::jsonb)
on conflict (role_name) do update set
  permissions = excluded.permissions;

-- 4) Create initial super admin (replace with your Firebase UID).
--
-- update public.profiles
-- set is_admin = true,
--     admin_role = 'super_admin'
-- where id = 'YOUR_ADMIN_FIREBASE_UID';

notify pgrst, 'reload schema';
