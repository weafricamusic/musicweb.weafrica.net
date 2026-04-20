-- Admin audit log (service-role only)

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

alter table public.admin_activity enable row level security;

-- Deny all for normal clients; the Supabase service-role bypasses RLS.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'admin_activity'
      and policyname = 'deny_all_admin_activity'
  ) then
    create policy deny_all_admin_activity
      on public.admin_activity
      for all
      using (false)
      with check (false);
  end if;
end $$;
