-- Lock Promotions table schema (Step 1 foundation)
-- Ensures required columns, defaults, and constraints exist.

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text not null default '',
  target_plan text not null default 'all' check (target_plan in ('all','free','premium')),
  is_active boolean not null default false,
  priority int not null default 0,
  starts_at timestamp,
  ends_at timestamp,
  created_at timestamp not null default now(),
  updated_at timestamp not null default now()
);

-- Add any missing columns (safe to run repeatedly)
alter table public.promotions
  add column if not exists title text;

alter table public.promotions
  add column if not exists description text;

alter table public.promotions
  add column if not exists image_url text;

alter table public.promotions
  add column if not exists target_plan text;

alter table public.promotions
  add column if not exists is_active boolean;

alter table public.promotions
  add column if not exists priority int;

alter table public.promotions
  add column if not exists starts_at timestamp;

alter table public.promotions
  add column if not exists ends_at timestamp;

alter table public.promotions
  add column if not exists created_at timestamp;

alter table public.promotions
  add column if not exists updated_at timestamp;

-- Enforce required constraints/defaults
alter table public.promotions
  alter column title set not null;

alter table public.promotions
  alter column image_url set default '';

alter table public.promotions
  alter column image_url set not null;

alter table public.promotions
  alter column target_plan set default 'all';

alter table public.promotions
  alter column target_plan set not null;

alter table public.promotions
  alter column is_active set default false;

alter table public.promotions
  alter column is_active set not null;

alter table public.promotions
  alter column priority set default 0;

alter table public.promotions
  alter column priority set not null;

alter table public.promotions
  alter column created_at set default now();

alter table public.promotions
  alter column created_at set not null;

alter table public.promotions
  alter column updated_at set default now();

alter table public.promotions
  alter column updated_at set not null;

-- Ensure types are correct (timestamp)
alter table public.promotions
  alter column starts_at type timestamp using starts_at::timestamp;

alter table public.promotions
  alter column ends_at type timestamp using ends_at::timestamp;

alter table public.promotions
  alter column created_at type timestamp using created_at::timestamp;

alter table public.promotions
  alter column updated_at type timestamp using updated_at::timestamp;

-- Ensure target_plan values are constrained
alter table public.promotions drop constraint if exists promotions_target_plan_check;
alter table public.promotions
  add constraint promotions_target_plan_check check (target_plan in ('all','free','premium'));

-- updated_at trigger helper + trigger
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'promotions_set_updated_at') then
    create trigger promotions_set_updated_at
      before update on public.promotions
      for each row
      execute function public.tg_set_updated_at();
  end if;
end $$;

-- RLS deny-all (admin uses service role)
alter table public.promotions enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'promotions'
      and policyname = 'deny_all_promotions'
  ) then
    create policy deny_all_promotions
      on public.promotions
      for all
      using (false)
      with check (false);
  end if;
end $$;

-- Indexes
create index if not exists promotions_is_active_idx on public.promotions (is_active);
create index if not exists promotions_priority_idx on public.promotions (priority desc);
create index if not exists promotions_starts_at_idx on public.promotions (starts_at);
create index if not exists promotions_ends_at_idx on public.promotions (ends_at);
