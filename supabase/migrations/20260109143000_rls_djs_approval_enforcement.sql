-- STEP 10.4 — SUPABASE RLS (HARD ENFORCEMENT): djs
--
-- Goals:
-- - Add `user_id` so DJs can be linked to auth.users
-- - Enable + force RLS
-- - Public (anon/authenticated) can READ only approved DJs
-- - DJ can READ their own profile (auth.uid() = djs.user_id)
-- - Admin remains unrestricted via service_role (bypasses RLS)

-- Needed for "DJ read own profile" policy
alter table public.djs
add column if not exists user_id uuid references auth.users (id) on delete set null;
alter table public.djs enable row level security;
alter table public.djs force row level security;
-- Hard enforcement: remove any existing/bypass policies on this table
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'djs'
  loop
    execute format('drop policy if exists %I on public.djs', pol.policyname);
  end loop;
end $$;
create policy "Public read approved DJs"
on public.djs
for select
to anon, authenticated
using (approved = true);
create policy "DJ read own profile"
on public.djs
for select
to authenticated
using (auth.uid()::text = user_id::text);
