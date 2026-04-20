-- RBAC: add Events/Tickets permission

-- Some environments may have an older `public.admins` table without these columns.
-- Ensure the view below can be created successfully.
do $$
begin
  if to_regclass('public.admins') is not null then
    alter table public.admins
      add column if not exists uid text,
      add column if not exists status text not null default 'active',
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists last_login_at timestamptz;
  end if;
end $$;
alter table public.role_permissions
  add column if not exists can_manage_events boolean not null default false;
-- Seed defaults (idempotent)
insert into public.role_permissions as rp (
  role,
  can_manage_users,
  can_manage_artists,
  can_manage_djs,
  can_manage_finance,
  can_stop_streams,
  can_manage_admins,
  can_view_logs,
  can_manage_events
) values
  ('super_admin', true, true, true, true, true, true, true, true),
  ('operations_admin', true, true, true, false, true, false, true, true),
  ('finance_admin', false, false, false, true, false, false, true, true),
  ('support_admin', false, false, false, false, false, false, true, false)
  on conflict (role) do update set
    can_manage_users = excluded.can_manage_users,
    can_manage_artists = excluded.can_manage_artists,
    can_manage_djs = excluded.can_manage_djs,
    can_manage_finance = excluded.can_manage_finance,
    can_stop_streams = excluded.can_stop_streams,
    can_manage_admins = excluded.can_manage_admins,
    can_view_logs = excluded.can_view_logs,
    can_manage_events = excluded.can_manage_events;
-- Update convenience view to expose new permission
create or replace view public.admins_with_permissions as
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
       p.can_view_logs,
       p.can_manage_events
from public.admins a
join public.role_permissions p on p.role = a.role;
notify pgrst, 'reload schema';
