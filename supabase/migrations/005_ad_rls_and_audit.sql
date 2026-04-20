-- RLS, admin mapping, and audit triggers for advertisement system
-- 1) Create an `app_admins` table to track which users are admins
-- 2) Enable RLS on the advertisement tables and add appropriate policies
-- 3) Create `ad_audit_logs` and triggers to store change history

-- Create app_admins mapping (admins should be inserted by a super-admin or the CLI)
create table if not exists app_admins (
  user_id text primary key,
  role text,
  added_at timestamptz default now()
);
-- Enable RLS on advertisements and related tables
alter table if exists advertisements enable row level security;
alter table if exists ad_impressions enable row level security;
alter table if exists ad_clicks enable row level security;
-- Policy: only admins may INSERT/UPDATE/DELETE advertisements
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'advertisements' and policyname = 'ads_admin_manage'
  ) then
    execute $pol$
      create policy ads_admin_manage on advertisements
        for all
        using (exists (select 1 from app_admins where user_id = auth.uid()::text))
        with check (exists (select 1 from app_admins where user_id = auth.uid()::text))
    $pol$;
  end if;
end $$;
-- Policy: public can SELECT active advertisements (or admins can see all)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'advertisements' and policyname = 'ads_public_select'
  ) then
    execute $pol$
      create policy ads_public_select on advertisements
        for select
        using ((status = 'active') OR (exists (select 1 from app_admins where user_id = auth.uid()::text)))
    $pol$;
  end if;
end $$;
-- Policy: allow any authenticated user to INSERT impressions/clicks (recording impressions/clicks from the client)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ad_impressions' and policyname = 'ad_impression_insert'
  ) then
    execute $pol$
      create policy ad_impression_insert on ad_impressions
        for insert
        with check (auth.uid() is not null)
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ad_clicks' and policyname = 'ad_click_insert'
  ) then
    execute $pol$
      create policy ad_click_insert on ad_clicks
        for insert
        with check (auth.uid() is not null)
    $pol$;
  end if;
end $$;
-- Policy: allow selects on impressions/clicks to admins only (analytics)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ad_impressions' and policyname = 'ad_impressions_select_admin'
  ) then
    execute $pol$
      create policy ad_impressions_select_admin on ad_impressions
        for select
        using (exists (select 1 from app_admins where user_id = auth.uid()::text))
    $pol$;
  end if;
end $$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ad_clicks' and policyname = 'ad_clicks_select_admin'
  ) then
    execute $pol$
      create policy ad_clicks_select_admin on ad_clicks
        for select
        using (exists (select 1 from app_admins where user_id = auth.uid()::text))
    $pol$;
  end if;
end $$;
-- Audit log table
create table if not exists ad_audit_logs (
  id serial primary key,
  ad_id integer,
  action text, -- insert | update | delete
  changed_by text,
  changed_at timestamptz default now(),
  old_row jsonb,
  new_row jsonb
);
-- Function to insert audit log on change
create or replace function fn_ad_audit() returns trigger as $$
begin
  if (TG_OP = 'INSERT') then
    insert into ad_audit_logs(ad_id, action, changed_by, new_row)
      values (NEW.id, 'insert', auth.uid(), row_to_json(NEW));
    return NEW;
  elsif (TG_OP = 'UPDATE') then
    insert into ad_audit_logs(ad_id, action, changed_by, old_row, new_row)
      values (NEW.id, 'update', auth.uid(), row_to_json(OLD), row_to_json(NEW));
    return NEW;
  elsif (TG_OP = 'DELETE') then
    insert into ad_audit_logs(ad_id, action, changed_by, old_row)
      values (OLD.id, 'delete', auth.uid(), row_to_json(OLD));
    return OLD;
  end if;
  return NULL;
end;
$$ language plpgsql security definer;
-- Attach triggers
drop trigger if exists trg_ad_audit on advertisements;
create trigger trg_ad_audit
  after insert or update or delete on advertisements
  for each row execute function fn_ad_audit();
-- Make audit table readable by admins only
alter table if exists ad_audit_logs enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ad_audit_logs' and policyname = 'ad_audit_select_admin'
  ) then
    execute $pol$
      create policy ad_audit_select_admin on ad_audit_logs
        for select
        using (exists (select 1 from app_admins where user_id = auth.uid()::text))
    $pol$;
  end if;
end $$;
-- Note: To grant an admin, insert a row into `app_admins`:
-- insert into app_admins (user_id, role) values ('<user-uuid>', 'superadmin');;
