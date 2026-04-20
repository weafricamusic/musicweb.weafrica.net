-- Legal documents (Terms of Service, Privacy Policy, etc.)
-- Provides a stable table for dashboards/clients to fetch published legal text.

create extension if not exists pgcrypto;

create table if not exists public.legal_documents (
  id bigserial primary key,

  -- Stable identifier (e.g. 'artist_tos', 'consumer_tos', 'privacy_policy')
  doc_key text not null,

  -- URL-friendly identifier some clients expect (e.g. 'artist-terms-of-service').
  slug text,

  title text not null,
  version text not null,

  -- Who this applies to
  audience text not null default 'all' check (audience in ('all','consumer','artist','dj','admin')),
  language text not null default 'en',

  -- Source-of-truth content (clients can render markdown).
  content_markdown text not null,

  -- Compatibility: some clients expect `legal_documents.content`.
  -- Keep it equal to content_markdown (markdown string).
  content text,

  -- Publication controls
  published boolean not null default false,
  effective_at timestamptz,

  meta jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (doc_key, version, audience, language)
);

-- If the table already existed in a legacy environment, ensure expected columns exist
-- before seed inserts.
alter table if exists public.legal_documents
  add column if not exists slug text,
  add column if not exists content text;

-- Backfill content for legacy rows.
update public.legal_documents
set content = coalesce(content, content_markdown)
where content is null;

create index if not exists legal_documents_doc_key_idx on public.legal_documents (doc_key);
create index if not exists legal_documents_published_idx on public.legal_documents (published, effective_at desc);

alter table public.legal_documents enable row level security;

-- Public read access to published + effective documents.
-- Note: this allows anon/authenticated reads (safe for legal docs).
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'legal_documents'
      and policyname = 'read_published_legal_documents'
  ) then
    create policy read_published_legal_documents
      on public.legal_documents
      for select
      using (
        published = true
        and (effective_at is null or effective_at <= now())
      );
  end if;
end $$;

-- Default deny for writes (keep changes service-role only).
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'legal_documents'
      and policyname = 'deny_writes_legal_documents'
  ) then
    create policy deny_writes_legal_documents
      on public.legal_documents
      for insert
      with check (false);

    create policy deny_updates_legal_documents
      on public.legal_documents
      for update
      using (false)
      with check (false);

    create policy deny_deletes_legal_documents
      on public.legal_documents
      for delete
      using (false);
  end if;
exception
  when duplicate_object then
    null;
end $$;

-- Convenience view: latest published document per (doc_key,audience,language).
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

-- Seed Artist Terms of Service v1 (minimal stub; update content_markdown later).
insert into public.legal_documents (doc_key, slug, title, version, audience, language, content, content_markdown, published, effective_at)
values (
  'artist_tos',
  'artist-terms-of-service',
  'WeAfrica Music – Artist Terms of Service',
  '1',
  'artist',
  'en',
  '## WeAfrica Music – Artist Terms of Service\n\nVersion 1\n',
  '## WeAfrica Music – Artist Terms of Service\n\nVersion 1\n',
  true,
  now()
)
on conflict (doc_key, version, audience, language) do update set
  slug = excluded.slug,
  title = excluded.title,
  content = excluded.content,
  content_markdown = excluded.content_markdown,
  published = excluded.published,
  effective_at = excluded.effective_at,
  updated_at = now();

-- Seed Content & Community Policy v1
insert into public.legal_documents (doc_key, slug, title, version, audience, language, content, content_markdown, published, effective_at)
values (
  'content_community_policy',
  'content-community-policy',
  'WeAfrica Music Content & Community Policy',
  '1',
  'all',
  'en',
  '## WeAfrica Music Content & Community Policy\n\nVersion 1\n',
  '## WeAfrica Music Content & Community Policy\n\nVersion 1\n',
  true,
  now()
)
on conflict (doc_key, version, audience, language) do update set
  slug = excluded.slug,
  title = excluded.title,
  content = excluded.content,
  content_markdown = excluded.content_markdown,
  published = excluded.published,
  effective_at = excluded.effective_at,
  updated_at = now();

-- Seed Copyright & Takedown Policy v1
insert into public.legal_documents (doc_key, slug, title, version, audience, language, content, content_markdown, published, effective_at)
values (
  'copyright_takedown_policy',
  'copyright-takedown-policy',
  'WeAfrica Music Copyright & Takedown Policy',
  '1',
  'all',
  'en',
  '## WeAfrica Music Copyright & Takedown Policy\n\nVersion 1\n',
  '## WeAfrica Music Copyright & Takedown Policy\n\nVersion 1\n',
  true,
  now()
)
on conflict (doc_key, version, audience, language) do update set
  slug = excluded.slug,
  title = excluded.title,
  content = excluded.content,
  content_markdown = excluded.content_markdown,
  published = excluded.published,
  effective_at = excluded.effective_at,
  updated_at = now();

notify pgrst, 'reload schema';
