-- Seed public.events rows where kind = EVENT and kind = LIVE (case depends on constraint).
-- Safe/conditional: only runs when public.events exists and has expected columns.

create extension if not exists pgcrypto;

do $$
declare
  kind_event text := 'EVENT';
  kind_live text := 'LIVE';
  seed_kind text;
  desired_values_id text;
  desired_values_no_id text;
  attempt int;
  has_id boolean;
  has_kind boolean;
  has_title boolean;
  has_subtitle boolean;
  has_city boolean;
  has_starts_at boolean;
  has_is_live boolean;
  missing_required text;
  cols_extra text := '';
  select_extra text := '';
  update_extra text := '';

  sql_upsert text;
  sql_insert_no_id text;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'events'
  ) then
    raise notice 'Skipping events seed; public.events does not exist.';
    return;
  end if;


  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'kind'
  ) into has_kind;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'title'
  ) into has_title;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'subtitle'
  ) into has_subtitle;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'city'
  ) into has_city;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'starts_at'
  ) into has_starts_at;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'is_live'
  ) into has_is_live;

  if not has_kind or not has_title then
    raise notice 'Skipping events seed; public.events missing kind/title columns.';
    return;
  end if;

  -- If there are unexpected NOT NULL columns with no defaults, skip to avoid breaking migration.
  select string_agg(column_name, ', ')
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'events'
    and is_nullable = 'NO'
    and column_default is null
    and column_name not in ('id','kind','title','subtitle','city','starts_at','is_live','created_at','updated_at')
  into missing_required;

  if missing_required is not null then
    raise notice 'Skipping events seed; public.events has required columns without defaults: %', missing_required;
    return;
  end if;

  if has_subtitle then
    cols_extra := cols_extra || ', subtitle';
    select_extra := select_extra || ', d.subtitle';
    update_extra := update_extra || ', subtitle = excluded.subtitle';
  end if;
  if has_city then
    cols_extra := cols_extra || ', city';
    select_extra := select_extra || ', d.city';
    update_extra := update_extra || ', city = excluded.city';
  end if;
  if has_starts_at then
    cols_extra := cols_extra || ', starts_at';
    select_extra := select_extra || ', d.starts_at';
    update_extra := update_extra || ', starts_at = excluded.starts_at';
  end if;
  if has_is_live then
    cols_extra := cols_extra || ', is_live';
    select_extra := select_extra || ', d.is_live';
    update_extra := update_extra || ', is_live = excluded.is_live';
  end if;

  -- Seed kind=EVENT (retry with lowercase if constraints/enums require it).
  desired_values_id :=
    '      (''3e2d5c1a-0c1f-4a2e-8c2b-6c3a7d9b1a01''::uuid, $1::text, ''WeAfrique Music Festival''::text, ''Annual showcase''::text, ''Lilongwe''::text, ''2026-03-01 18:00:00+00''::timestamptz, false::boolean),\n'
    || '      (''d62e1a55-5cc3-4e4d-9f1a-7f5b0d2b9e12''::uuid, $1::text, ''WeAfrique Battle Night''::text, ''Community battles & performances''::text, ''Blantyre''::text, ''2026-03-08 18:00:00+00''::timestamptz, false::boolean),\n'
    || '      (''a9c7f3d0-8f1e-4c15-a6b1-2c5a1f0d7e33''::uuid, $1::text, ''WeAfrique VIP Listening Party''::text, ''Premieres & meetups''::text, ''Mzuzu''::text, ''2026-03-15 18:00:00+00''::timestamptz, false::boolean)';
  desired_values_no_id :=
    '      ($1::text, ''WeAfrique Music Festival''::text, ''Annual showcase''::text, ''Lilongwe''::text, ''2026-03-01 18:00:00+00''::timestamptz, false::boolean),\n'
    || '      ($1::text, ''WeAfrique Battle Night''::text, ''Community battles & performances''::text, ''Blantyre''::text, ''2026-03-08 18:00:00+00''::timestamptz, false::boolean),\n'
    || '      ($1::text, ''WeAfrique VIP Listening Party''::text, ''Premieres & meetups''::text, ''Mzuzu''::text, ''2026-03-15 18:00:00+00''::timestamptz, false::boolean)';

  seed_kind := kind_event;
  for attempt in 1..2 loop
    begin
      if has_id then
        sql_upsert :=
          'with desired as (\n'
          || '  select *\n'
          || '  from (\n'
          || '    values\n'
          || desired_values_id || '\n'
          || '  ) as v(id, kind, title, subtitle, city, starts_at, is_live)\n'
          || ')\n'
          || 'insert into public.events (id, kind, title' || cols_extra || ')\n'
          || 'select d.id, d.kind, d.title' || select_extra || '\n'
          || 'from desired d\n'
          || 'on conflict (id) do update set\n'
          || '  kind = excluded.kind,\n'
          || '  title = excluded.title' || update_extra || ';';

        execute sql_upsert using seed_kind;
      else
        sql_insert_no_id :=
          'with desired as (\n'
          || '  select *\n'
          || '  from (\n'
          || '    values\n'
          || desired_values_no_id || '\n'
          || '  ) as v(kind, title, subtitle, city, starts_at, is_live)\n'
          || ')\n'
          || 'insert into public.events (kind, title' || cols_extra || ')\n'
          || 'select d.kind, d.title' || select_extra || '\n'
          || 'from desired d\n'
          || 'where not exists (\n'
          || '  select 1\n'
          || '  from public.events e\n'
          || '  where e.kind = d.kind\n'
          || '    and e.title = d.title\n'
          || (case when has_starts_at then '    and e.starts_at = d.starts_at\n' else '' end)
          || ');';

        execute sql_insert_no_id using seed_kind;
      end if;
      exit;
    exception
      when check_violation or invalid_text_representation then
        if attempt = 1 then
          seed_kind := lower(seed_kind);
        else
          raise;
        end if;
    end;
  end loop;

  -- Seed kind=LIVE (retry with lowercase if constraints/enums require it).
  desired_values_id :=
    '      (''4c0f2f71-1f19-4e36-9c7b-8b8b62d3a401''::uuid, $1::text, ''WeAfrique Live Session''::text, ''Live DJ set''::text, ''Online''::text, ''2026-03-02 19:00:00+00''::timestamptz, true::boolean),\n'
    || '      (''b8c93b74-7e8b-4a7e-98b5-4aa9d68ac512''::uuid, $1::text, ''WeAfrique Live Battle''::text, ''Live battles''::text, ''Online''::text, ''2026-03-09 19:00:00+00''::timestamptz, true::boolean)';
  desired_values_no_id :=
    '      ($1::text, ''WeAfrique Live Session''::text, ''Live DJ set''::text, ''Online''::text, ''2026-03-02 19:00:00+00''::timestamptz, true::boolean),\n'
    || '      ($1::text, ''WeAfrique Live Battle''::text, ''Live battles''::text, ''Online''::text, ''2026-03-09 19:00:00+00''::timestamptz, true::boolean)';

  seed_kind := kind_live;
  for attempt in 1..2 loop
    begin
      if has_id then
        sql_upsert :=
          'with desired as (\n'
          || '  select *\n'
          || '  from (\n'
          || '    values\n'
          || desired_values_id || '\n'
          || '  ) as v(id, kind, title, subtitle, city, starts_at, is_live)\n'
          || ')\n'
          || 'insert into public.events (id, kind, title' || cols_extra || ')\n'
          || 'select d.id, d.kind, d.title' || select_extra || '\n'
          || 'from desired d\n'
          || 'on conflict (id) do update set\n'
          || '  kind = excluded.kind,\n'
          || '  title = excluded.title' || update_extra || ';';

        execute sql_upsert using seed_kind;
      else
        sql_insert_no_id :=
          'with desired as (\n'
          || '  select *\n'
          || '  from (\n'
          || '    values\n'
          || desired_values_no_id || '\n'
          || '  ) as v(kind, title, subtitle, city, starts_at, is_live)\n'
          || ')\n'
          || 'insert into public.events (kind, title' || cols_extra || ')\n'
          || 'select d.kind, d.title' || select_extra || '\n'
          || 'from desired d\n'
          || 'where not exists (\n'
          || '  select 1\n'
          || '  from public.events e\n'
          || '  where e.kind = d.kind\n'
          || '    and e.title = d.title\n'
          || (case when has_starts_at then '    and e.starts_at = d.starts_at\n' else '' end)
          || ');';

        execute sql_insert_no_id using seed_kind;
      end if;
      exit;
    exception
      when check_violation or invalid_text_representation then
        if attempt = 1 then
          seed_kind := lower(seed_kind);
        else
          raise;
        end if;
    end;
  end loop;

  raise notice 'Seeded/updated public.events rows for kind=% and kind=%', kind_event, kind_live;
end $$;

-- Refresh PostgREST schema cache (helps avoid transient PGRST205 after migrations)
notify pgrst, 'reload schema';
