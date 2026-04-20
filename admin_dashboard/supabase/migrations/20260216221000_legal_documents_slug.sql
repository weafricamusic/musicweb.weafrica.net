-- Follow-up: add `slug` column to legal_documents for clients that expect it.
-- Safe to run on environments that already applied the initial legal_documents migration.

alter table if exists public.legal_documents
  add column if not exists slug text;

alter table if exists public.legal_documents
  add column if not exists content text;

update public.legal_documents
set content = coalesce(content, content_markdown)
where content is null;

-- Backfill slug for existing rows (best-effort).
-- Default to a URL-safe transform of doc_key.
update public.legal_documents
set slug = coalesce(
  nullif(trim(slug), ''),
  replace(lower(trim(doc_key)), '_', '-')
)
where slug is null or trim(slug) = '';

-- Ensure the seeded artist_tos has a nice slug.
update public.legal_documents
set slug = 'artist-terms-of-service'
where doc_key = 'artist_tos'
  and (slug is null or slug = 'artist-tos' or slug = 'artist_tos' or slug = replace(lower(trim(doc_key)), '_', '-'));

-- Uniqueness for lookups.
create unique index if not exists legal_documents_slug_version_unique
  on public.legal_documents (slug, version, audience, language)
  where slug is not null;

-- Refresh the public view to include slug (idempotent).
-- Drop first to avoid Postgres error 42P16 when column order changes across versions.
drop view if exists public.current_legal_documents;
create view public.current_legal_documents as
select distinct on (doc_key, audience, language)
  doc_key,
  slug,
  audience,
  language,
  title,
  version,
  content,
  content_markdown,
  effective_at,
  published,
  meta,
  created_at,
  updated_at
from public.legal_documents
where published = true
  and (effective_at is null or effective_at <= now())
order by doc_key, audience, language, effective_at desc nulls last, created_at desc;

notify pgrst, 'reload schema';
