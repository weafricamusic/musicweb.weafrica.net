-- Repair + seed legal documents across schema variants.
--
-- Why this exists:
-- - Some environments created public.legal_documents earlier with a different column set.
-- - Clients may query by doc_key/slug and expect rows to exist.
--
-- This migration:
-- - Adds commonly expected columns (best-effort, idempotent)
-- - Upserts the v1 docs (Artist ToS, Content & Community Policy, Copyright & Takedown)

do $$
declare
  has_slug boolean;
  has_content boolean;
  has_content_markdown boolean;
  has_published boolean;
  has_effective_at boolean;
  has_meta boolean;
  has_audience boolean;
  has_language boolean;
  has_version boolean;
  has_title boolean;
  has_doc_key boolean;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'legal_documents'
  ) then
    raise notice 'legal_documents missing; apply 20260216214000_legal_documents.sql first.';
    return;
  end if;

  -- Best-effort column adds (do not fail migration if a column cannot be added).
  begin
    alter table public.legal_documents add column if not exists slug text;
  exception when others then null;
  end;

  begin
    alter table public.legal_documents add column if not exists content text;
  exception when others then null;
  end;

  begin
    alter table public.legal_documents add column if not exists content_markdown text;
  exception when others then null;
  end;

  begin
    alter table public.legal_documents add column if not exists published boolean;
  exception when others then null;
  end;

  begin
    alter table public.legal_documents add column if not exists effective_at timestamptz;
  exception when others then null;
  end;

  begin
    alter table public.legal_documents add column if not exists meta jsonb;
  exception when others then null;
  end;

  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='doc_key'
  ) into has_doc_key;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='title'
  ) into has_title;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='version'
  ) into has_version;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='audience'
  ) into has_audience;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='language'
  ) into has_language;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='slug'
  ) into has_slug;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='content'
  ) into has_content;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='content_markdown'
  ) into has_content_markdown;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='published'
  ) into has_published;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='effective_at'
  ) into has_effective_at;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='meta'
  ) into has_meta;

  if not (has_doc_key and has_title and has_version) then
    raise notice 'legal_documents missing required columns (doc_key/title/version); skipping seed.';
    return;
  end if;

  -- Upsert by (doc_key,version,audience,language) when possible; otherwise do a doc_key+version best-effort.
  -- Build per-document update then insert-if-missing to avoid relying on a specific unique constraint.

  -- Helper: normalize existing rows (content/content_markdown/meta).
  if has_content and has_content_markdown then
    update public.legal_documents set content = coalesce(content, content_markdown) where content is null;
    update public.legal_documents set content_markdown = coalesce(content_markdown, content) where content_markdown is null;
  elsif has_content and not has_content_markdown then
    -- nothing
  elsif has_content_markdown and not has_content then
    -- nothing
  end if;

  if has_meta then
    update public.legal_documents set meta = coalesce(meta, '{}'::jsonb) where meta is null;
  end if;

  -- Artist ToS v1
  update public.legal_documents
  set
    title = 'WeAfrica Music – Artist Terms of Service',
    version = '1'
    ,updated_at = coalesce(updated_at, now())
  where doc_key = 'artist_tos'
    and version = '1'
    and (not has_audience or audience = 'artist')
    and (not has_language or language = 'en');

  if has_slug then
    update public.legal_documents
    set slug = coalesce(nullif(trim(slug), ''), 'artist-terms-of-service')
    where doc_key = 'artist_tos' and version = '1';
  end if;

  if has_content then
    update public.legal_documents
    set content = coalesce(content, '## WeAfrica Music – Artist Terms of Service\n\nVersion 1\n')
    where doc_key = 'artist_tos' and version = '1';
  end if;

  if has_content_markdown then
    update public.legal_documents
    set content_markdown = coalesce(content_markdown, '## WeAfrica Music – Artist Terms of Service\n\nVersion 1\n')
    where doc_key = 'artist_tos' and version = '1';
  end if;

  if has_published then
    update public.legal_documents
    set published = coalesce(published, true)
    where doc_key = 'artist_tos' and version = '1';
  end if;

  if has_effective_at then
    update public.legal_documents
    set effective_at = coalesce(effective_at, now())
    where doc_key = 'artist_tos' and version = '1';
  end if;

  -- Insert if missing
  if not exists (select 1 from public.legal_documents where doc_key='artist_tos' and version='1') then
    insert into public.legal_documents (doc_key, title, version)
    values ('artist_tos', 'WeAfrica Music – Artist Terms of Service', '1');
  end if;

  -- Content & Community Policy v1
  if not exists (select 1 from public.legal_documents where doc_key='content_community_policy' and version='1') then
    insert into public.legal_documents (doc_key, title, version)
    values ('content_community_policy', 'WeAfrica Music Content & Community Policy', '1');
  end if;

  if has_slug then
    update public.legal_documents set slug = coalesce(nullif(trim(slug), ''), 'content-community-policy')
    where doc_key='content_community_policy' and version='1';
  end if;
  if has_content then
    update public.legal_documents set content = coalesce(content, '## WeAfrica Music Content & Community Policy\n\nVersion 1\n')
    where doc_key='content_community_policy' and version='1';
  end if;
  if has_content_markdown then
    update public.legal_documents set content_markdown = coalesce(content_markdown, '## WeAfrica Music Content & Community Policy\n\nVersion 1\n')
    where doc_key='content_community_policy' and version='1';
  end if;
  if has_published then
    update public.legal_documents set published = coalesce(published, true)
    where doc_key='content_community_policy' and version='1';
  end if;
  if has_effective_at then
    update public.legal_documents set effective_at = coalesce(effective_at, now())
    where doc_key='content_community_policy' and version='1';
  end if;

  -- Copyright & Takedown Policy v1
  if not exists (select 1 from public.legal_documents where doc_key='copyright_takedown_policy' and version='1') then
    insert into public.legal_documents (doc_key, title, version)
    values ('copyright_takedown_policy', 'WeAfrica Music Copyright & Takedown Policy', '1');
  end if;

  if has_slug then
    update public.legal_documents set slug = coalesce(nullif(trim(slug), ''), 'copyright-takedown-policy')
    where doc_key='copyright_takedown_policy' and version='1';
  end if;
  if has_content then
    update public.legal_documents set content = coalesce(content, '## WeAfrica Music Copyright & Takedown Policy\n\nVersion 1\n')
    where doc_key='copyright_takedown_policy' and version='1';
  end if;
  if has_content_markdown then
    update public.legal_documents set content_markdown = coalesce(content_markdown, '## WeAfrica Music Copyright & Takedown Policy\n\nVersion 1\n')
    where doc_key='copyright_takedown_policy' and version='1';
  end if;
  if has_published then
    update public.legal_documents set published = coalesce(published, true)
    where doc_key='copyright_takedown_policy' and version='1';
  end if;
  if has_effective_at then
    update public.legal_documents set effective_at = coalesce(effective_at, now())
    where doc_key='copyright_takedown_policy' and version='1';
  end if;

  -- Audience/language backfill if those columns exist but were left NULL.
  if has_audience then
    update public.legal_documents set audience = coalesce(audience, 'artist') where doc_key='artist_tos' and version='1';
    update public.legal_documents set audience = coalesce(audience, 'all') where doc_key in ('content_community_policy','copyright_takedown_policy') and version='1';
  end if;
  if has_language then
    update public.legal_documents set language = coalesce(language, 'en') where version='1' and doc_key in ('artist_tos','content_community_policy','copyright_takedown_policy');
  end if;

  notify pgrst, 'reload schema';
end $$;
