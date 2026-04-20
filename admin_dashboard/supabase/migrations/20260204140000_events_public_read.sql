-- Allow consumer app read access to public.events (for Home/Live listings).
-- Applies GRANT SELECT unconditionally when table exists.
-- Adds a read policy only if RLS is already enabled on public.events.

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'events'
  ) then
    execute 'grant select on table public.events to anon, authenticated';

    -- If RLS is enabled, ensure a read policy exists.
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'events'
        and c.relrowsecurity = true
    ) then
      if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'events'
          and policyname = 'public_read_events'
      ) then
        -- Build a safe policy condition depending on available columns.
        if exists (
          select 1
          from information_schema.columns
          where table_schema = 'public'
            and table_name = 'events'
            and column_name = 'is_active'
        ) then
          execute 'create policy public_read_events on public.events for select using (is_active = true)';
        elsif exists (
          select 1
          from information_schema.columns
          where table_schema = 'public'
            and table_name = 'events'
            and column_name = 'status'
        ) then
          execute 'create policy public_read_events on public.events for select using (status = ''active'')';
        else
          execute 'create policy public_read_events on public.events for select using (true)';
        end if;
      end if;
    end if;
  end if;
end $$;
