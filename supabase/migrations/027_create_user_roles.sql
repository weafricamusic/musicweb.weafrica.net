-- Adds multi-role support for a single Firebase-backed user identity.
--
-- NOTE:
-- This app uses Firebase Auth UIDs (text) throughout the database (e.g., `profiles.id`, `wallets.user_id`).
-- So `user_roles.user_id` is `text`, not `uuid references auth.users(id)`.

create table if not exists public.user_roles (
  user_id text not null,
  role text not null check (role in ('consumer','artist','dj','admin')),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);
-- Optional indexes for common lookups
create index if not exists user_roles_user_id_idx on public.user_roles (user_id);
create index if not exists user_roles_role_idx on public.user_roles (role);
-- RLS is intentionally NOT enabled here because this project commonly uses
-- Firebase Auth (not Supabase Auth). Enable RLS only if you also authenticate
-- requests to Supabase in a way that makes `auth.uid()` meaningful.;
