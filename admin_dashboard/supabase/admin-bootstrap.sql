-- Admin roles table for role-based access control

create table if not exists public.admin_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('super_admin', 'admin')),
  created_at timestamptz not null default now()
);

alter table public.admin_roles enable row level security;

-- Allow signed-in users to read their own role row (used by the admin UI to verify admin access)
do $$
begin
  create policy "Admins can read own role"
    on public.admin_roles
    for select
    to authenticated
    using (auth.uid() = user_id);
exception
  when duplicate_object then null;
end $$;
