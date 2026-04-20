-- Seed additional legal policies (idempotent).
-- This is a safety net for environments that already ran the initial legal_documents migration.

insert into public.legal_documents (doc_key, slug, title, version, audience, language, content_markdown, published, effective_at)
values
  (
    'content_community_policy',
    'content-community-policy',
    'WeAfrica Music Content & Community Policy',
    '1',
    'all',
    'en',
    '## WeAfrica Music Content & Community Policy\n\nVersion 1\n',
    true,
    now()
  ),
  (
    'copyright_takedown_policy',
    'copyright-takedown-policy',
    'WeAfrica Music Copyright & Takedown Policy',
    '1',
    'all',
    'en',
    '## WeAfrica Music Copyright & Takedown Policy\n\nVersion 1\n',
    true,
    now()
  )
on conflict (doc_key, version, audience, language) do update set
  slug = excluded.slug,
  title = excluded.title,
  content_markdown = excluded.content_markdown,
  published = excluded.published,
  effective_at = excluded.effective_at,
  updated_at = now();

notify pgrst, 'reload schema';
