-- Seed initial admin accounts. Replace emails before running.
-- Example usage:
--   update these emails, then run: supabase db push

insert into public.admins (email, role, status)
values
  ('founder@example.com', 'super_admin', 'active'),
  ('ops@example.com', 'operations_admin', 'active'),
  ('finance@example.com', 'finance_admin', 'active'),
  ('support@example.com', 'support_admin', 'active')
  on conflict (email) do update set role = excluded.role, status = excluded.status;
