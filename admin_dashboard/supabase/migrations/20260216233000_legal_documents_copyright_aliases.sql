-- Compatibility: some clients look up the copyright policy under different keys/slugs.
-- This migration seeds alias rows that point to the same v1 policy content.

do $$
declare
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

  -- Ensure the canonical row exists (best-effort; earlier migrations should have created it).
  if not exists (
    select 1
    from public.legal_documents
    where doc_key = 'copyright_takedown_policy'
      and version = '1'
      and audience = 'all'
      and (not has_language or language = 'en')
  ) then
    -- Nothing to alias from.
    return;
  end if;

  -- Alias 1: doc_key=copyright_policy, slug=copyright-policy
  if not exists (
    select 1
    from public.legal_documents
    where doc_key = 'copyright_policy'
      and version = '1'
      and audience = 'all'
      and (not has_language or language = 'en')
  ) then
    insert into public.legal_documents (doc_key, slug, title, version, audience, language, content, content_markdown, published, effective_at)
    select
      'copyright_policy',
      case when has_slug then 'copyright-policy' else null end,
      'WeAfrica Music Copyright Policy',
      '1',
      'all',
      case when has_language then 'en' else null end,
      case when has_content then coalesce(content, content_markdown) else null end,
      case when has_content_markdown then coalesce(content_markdown, content) else null end,
      case when has_published then coalesce(published, true) else null end,
      case when has_effective_at then coalesce(effective_at, now()) else null end
    from public.legal_documents
    where doc_key = 'copyright_takedown_policy'
      and version = '1'
      and audience = 'all'
    limit 1;
  end if;

  -- Alias 2: doc_key=copyright_and_takedown_policy, slug=copyright-and-takedown-policy
  if not exists (
    select 1
    from public.legal_documents
    where doc_key = 'copyright_and_takedown_policy'
      and version = '1'
      and audience = 'all'
      and (not has_language or language = 'en')
  ) then
    insert into public.legal_documents (doc_key, slug, title, version, audience, language, content, content_markdown, published, effective_at)
    select
      'copyright_and_takedown_policy',
      case when has_slug then 'copyright-and-takedown-policy' else null end,
      'WeAfrica Music Copyright & Takedown Policy',
      '1',
      'all',
      case when has_language then 'en' else null end,
      case when has_content then coalesce(content, content_markdown) else null end,
      case when has_content_markdown then coalesce(content_markdown, content) else null end,
      case when has_published then coalesce(published, true) else null end,
      case when has_effective_at then coalesce(effective_at, now()) else null end
    from public.legal_documents
    where doc_key = 'copyright_takedown_policy'
      and version = '1'
      and audience = 'all'
    limit 1;
  end if;

  notify pgrst, 'reload schema';
end $$;
