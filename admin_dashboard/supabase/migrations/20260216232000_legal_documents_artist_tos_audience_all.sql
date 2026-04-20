-- Compatibility: some clients look up artist ToS as audience='all'.
-- This migration ensures an `artist_tos` v1 row exists for audience=all (published).

do $$
declare
  has_audience boolean;
  has_language boolean;
  has_slug boolean;
  has_published boolean;
  has_effective_at boolean;
  has_content boolean;
  has_content_markdown boolean;
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'legal_documents'
  ) then
    return;
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='audience'
  ) into has_audience;

  if not has_audience then
    return;
  end if;

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
    where table_schema='public' and table_name='legal_documents' and column_name='published'
  ) into has_published;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='effective_at'
  ) into has_effective_at;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='content'
  ) into has_content;
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='legal_documents' and column_name='content_markdown'
  ) into has_content_markdown;

  if not exists (
    select 1
    from public.legal_documents
    where doc_key = 'artist_tos'
      and version = '1'
      and audience = 'all'
      and (not has_language or language = 'en')
  ) then
    insert into public.legal_documents (doc_key, slug, title, version, audience, language, content, content_markdown, published, effective_at)
    select
      doc_key,
      case when has_slug then coalesce(nullif(trim(slug), ''), 'artist-terms-of-service') else null end,
      title,
      version,
      'all',
      case when has_language then coalesce(nullif(trim(language), ''), 'en') else null end,
      case when has_content then coalesce(content, content_markdown, '## WeAfrica Music – Artist Terms of Service\n\nVersion 1\n') else null end,
      case when has_content_markdown then coalesce(content_markdown, content, '## WeAfrica Music – Artist Terms of Service\n\nVersion 1\n') else null end,
      case when has_published then coalesce(published, true) else null end,
      case when has_effective_at then coalesce(effective_at, now()) else null end
    from public.legal_documents
    where doc_key = 'artist_tos'
      and version = '1'
      and audience = 'artist'
    limit 1;
  end if;

  -- Ensure view is refreshed (if it exists) by nudging PostgREST.
  notify pgrst, 'reload schema';
end $$;
