-- PostgREST compatibility for wallet storage
--
-- Some clients probe for wallet tables via the REST schema cache using anon/authenticated keys.
-- If privileges are fully revoked, PostgREST will behave as if the table does not exist (PGRST205).
--
-- This migration:
-- - Ensures anon/authenticated have *schema visibility* (GRANT SELECT) on dj_wallets.
-- - Adds legacy aliases (views) public.dj_wallet and public.wallets when missing.
-- - Keeps RLS deny-all from the base migration; data access remains blocked until policies are added.

-- Make table visible to PostgREST for anon/authenticated.
-- With RLS enabled + deny-all policies, SELECT returns zero rows.
grant usage on schema public to anon, authenticated;
grant select on table public.dj_wallets to anon, authenticated;

-- Optional: allow service_role full access
grant all on table public.dj_wallets to service_role;

-- Create legacy alias views only if they don't already exist.
DO $$
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'dj_wallet'
  ) then
    execute $view$
      create view public.dj_wallet as
      select * from public.dj_wallets;
    $view$;
    grant select on table public.dj_wallet to anon, authenticated;
    grant all on table public.dj_wallet to service_role;
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'wallets'
  ) then
    execute $view$
      create view public.wallets as
      select * from public.dj_wallets;
    $view$;
    grant select on table public.wallets to anon, authenticated;
    grant all on table public.wallets to service_role;
  end if;
end $$;

-- Hint PostgREST to refresh schema cache.
notify pgrst, 'reload schema';
