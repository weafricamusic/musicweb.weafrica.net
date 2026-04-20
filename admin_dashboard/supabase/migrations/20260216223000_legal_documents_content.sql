-- Follow-up: add `content` column to legal_documents for clients that expect it.
-- Keeps `content` populated from `content_markdown`.

alter table if exists public.legal_documents
  add column if not exists content text;

update public.legal_documents
set content = coalesce(content, content_markdown)
where content is null;

-- Refresh view to include `content` (drop first to avoid 42P16).
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
