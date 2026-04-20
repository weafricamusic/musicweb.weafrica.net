-- Promotions (Phase 1 foundation)
-- Source of truth for consumer-visible promotions.

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text not null default '',
  target_plan text not null default 'all' check (target_plan in ('all','free','premium')),
  is_active boolean not null default false,
  priority int not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists promotions_is_active_idx on public.promotions (is_active);
create index if not exists promotions_priority_idx on public.promotions (priority desc);
create index if not exists promotions_starts_at_idx on public.promotions (starts_at);
create index if not exists promotions_ends_at_idx on public.promotions (ends_at);
-- Ensure the shared updated_at trigger helper exists (defined in other migrations too).
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
alter table public.promotions enable row level security;
-- Default to deny-all; admin uses service role for writes/reads.
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
