-- Promotions system alignment
--
-- Purpose:
-- - bring the existing promotions engine in line with the app/admin routes
-- - add plan tiers, content references, social posting logs, and feed bonus metadata
-- - keep all changes idempotent for mixed environments

create extension if not exists pgcrypto;

alter table public.promotions
  add column if not exists title text,
  add column if not exists promotion_type text,
  add column if not exists target_id text,
  add column if not exists budget_coins integer,
  add column if not exists status text,
  add column if not exists is_active boolean not null default false,
  add column if not exists start_date timestamptz,
  add column if not exists end_date timestamptz,
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists user_id text,
  add column if not exists content_id text,
  add column if not exists content_type text,
  add column if not exists plan text,
  add column if not exists duration_days integer,
  add column if not exists featured_badge text,
  add column if not exists feed_boost_multiplier numeric not null default 1,
  add column if not exists promotion_score_bonus integer not null default 0,
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by text,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejected_by text,
  add column if not exists completed_at timestamptz,
  add column if not exists facebook_page_url text,
  add column if not exists instagram_url text,
  add column if not exists x_url text,
  add column if not exists whatsapp_channel_url text;

update public.promotions
set
  content_id = coalesce(nullif(content_id, ''), nullif(target_id, '')),
  content_type = coalesce(nullif(content_type, ''), case when promotion_type in ('artist', 'dj', 'battle', 'event', 'ride') then promotion_type else 'song' end),
  plan = coalesce(nullif(plan, ''), case
    when coalesce(budget_coins, 0) >= 500 then 'premium'
    when coalesce(budget_coins, 0) >= 200 then 'pro'
    when coalesce(budget_coins, 0) > 0 then 'basic'
    else null
  end),
  duration_days = coalesce(
    duration_days,
    case
      when start_date is not null and end_date is not null then greatest(1, ceil(extract(epoch from (end_date - start_date)) / 86400.0)::integer)
      when starts_at is not null and ends_at is not null then greatest(1, ceil(extract(epoch from (ends_at - starts_at)) / 86400.0)::integer)
      else null
    end
  ),
  featured_badge = coalesce(nullif(featured_badge, ''), case when plan = 'premium' then 'banner' when plan = 'pro' then 'featured' else 'none' end),
  facebook_page_url = coalesce(nullif(facebook_page_url, ''), 'https://www.facebook.com/share/1DzRfNVBSc/'),
  instagram_url = coalesce(nullif(instagram_url, ''), 'https://www.instagram.com/weafricamusic?igsh=b3l0eHc3cm5zNmQx'),
  x_url = coalesce(nullif(x_url, ''), 'https://x.com/WeafricaMusic'),
  whatsapp_channel_url = coalesce(nullif(whatsapp_channel_url, ''), 'https://whatsapp.com/channel/0029VbCKK5V0gcfObTkWfT12')
where true;

alter table public.promotions
  alter column feed_boost_multiplier set default 1,
  alter column promotion_score_bonus set default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'promotions_plan_check_v1'
  ) then
    alter table public.promotions
      add constraint promotions_plan_check_v1
      check (plan is null or plan in ('basic', 'pro', 'premium'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'promotions_content_type_check_v1'
  ) then
    alter table public.promotions
      add constraint promotions_content_type_check_v1
      check (content_type is null or content_type in ('song', 'video', 'artist', 'dj', 'battle', 'event', 'ride'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'promotions_duration_days_positive_v1'
  ) then
    alter table public.promotions
      add constraint promotions_duration_days_positive_v1
      check (duration_days is null or duration_days > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'promotions_featured_badge_check_v1'
  ) then
    alter table public.promotions
      add constraint promotions_featured_badge_check_v1
      check (featured_badge is null or featured_badge in ('none', 'featured', 'banner'));
  end if;
end $$;

create index if not exists promotions_content_id_idx_v2 on public.promotions (content_id);
create index if not exists promotions_content_type_idx_v2 on public.promotions (content_type);
create index if not exists promotions_plan_idx_v1 on public.promotions (plan);

create table if not exists public.paid_promotions (
  id uuid primary key default gen_random_uuid(),
  user_id text,
  content_id text,
  content_type text,
  title text,
  coins integer not null default 0,
  duration integer,
  duration_days integer,
  country text,
  audience text,
  surface text,
  plan text,
  status text not null default 'pending',
  review_note text,
  reviewer_email text,
  reviewer_note text,
  activated_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text,
  starts_at timestamptz,
  ends_at timestamptz,
  promotion_id uuid,
  facebook_page_url text,
  instagram_url text,
  x_url text,
  whatsapp_channel_url text
);

alter table public.paid_promotions
  add column if not exists title text,
  add column if not exists duration integer,
  add column if not exists duration_days integer,
  add column if not exists plan text,
  add column if not exists surface text,
  add column if not exists review_note text,
  add column if not exists reviewer_email text,
  add column if not exists reviewer_note text,
  add column if not exists activated_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists facebook_page_url text,
  add column if not exists instagram_url text,
  add column if not exists x_url text,
  add column if not exists whatsapp_channel_url text;

update public.paid_promotions
set
  duration_days = coalesce(duration_days, duration),
  plan = coalesce(nullif(plan, ''), case
    when coalesce(coins, 0) >= 500 then 'premium'
    when coalesce(coins, 0) >= 200 then 'pro'
    when coalesce(coins, 0) > 0 then 'basic'
    else null
  end),
  surface = coalesce(nullif(surface, ''), 'feed'),
  reviewer_note = coalesce(reviewer_note, review_note),
  facebook_page_url = coalesce(nullif(facebook_page_url, ''), 'https://www.facebook.com/share/1DzRfNVBSc/'),
  instagram_url = coalesce(nullif(instagram_url, ''), 'https://www.instagram.com/weafricamusic?igsh=b3l0eHc3cm5zNmQx'),
  x_url = coalesce(nullif(x_url, ''), 'https://x.com/WeafricaMusic'),
  whatsapp_channel_url = coalesce(nullif(whatsapp_channel_url, ''), 'https://whatsapp.com/channel/0029VbCKK5V0gcfObTkWfT12')
where true;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'paid_promotions_duration_days_positive_v1'
  ) then
    alter table public.paid_promotions
      add constraint paid_promotions_duration_days_positive_v1
      check (duration_days is null or duration_days > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'paid_promotions_plan_check_v1'
  ) then
    alter table public.paid_promotions
      add constraint paid_promotions_plan_check_v1
      check (plan is null or plan in ('basic', 'pro', 'premium'));
  end if;
end $$;

create index if not exists paid_promotions_plan_idx_v1 on public.paid_promotions (plan);
create index if not exists paid_promotions_duration_days_idx_v1 on public.paid_promotions (duration_days);

create table if not exists public.promotion_events (
  id bigserial primary key,
  promotion_id uuid,
  paid_promotion_id uuid,
  event_type text,
  country text,
  country_code text,
  actor_id text,
  meta jsonb not null default '{}'::jsonb,
  session_id text,
  user_uid text,
  created_at timestamptz not null default now(),
  properties jsonb not null default '{}'::jsonb
);

alter table public.promotion_events
  add column if not exists country text,
  add column if not exists country_code text,
  add column if not exists actor_id text,
  add column if not exists meta jsonb not null default '{}'::jsonb,
  add column if not exists session_id text,
  add column if not exists user_uid text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists properties jsonb not null default '{}'::jsonb;

update public.promotion_events
set
  country_code = coalesce(nullif(country_code, ''), nullif(country, '')),
  properties = coalesce(properties, meta, '{}'::jsonb),
  user_uid = coalesce(nullif(user_uid, ''), nullif(actor_id, ''))
where true;

create index if not exists promotion_events_country_code_idx_v1 on public.promotion_events (country_code, created_at desc);
create index if not exists promotion_events_user_uid_idx_v1 on public.promotion_events (user_uid, created_at desc);

create table if not exists public.promotion_posts (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  platform text not null,
  status text not null default 'pending',
  post_link text,
  message_text text,
  admin_id text,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint promotion_posts_platform_check_v1 check (platform in ('facebook', 'instagram', 'x', 'whatsapp')),
  constraint promotion_posts_status_check_v1 check (status in ('pending', 'posted', 'skipped'))
);

create index if not exists promotion_posts_promotion_idx_v1 on public.promotion_posts (promotion_id, created_at desc);
create index if not exists promotion_posts_platform_idx_v1 on public.promotion_posts (platform, created_at desc);
create index if not exists promotion_posts_status_idx_v1 on public.promotion_posts (status, created_at desc);

alter table public.promotion_posts enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'promotion_posts_set_updated_at'
  ) then
    create trigger promotion_posts_set_updated_at
      before update on public.promotion_posts
      for each row
      execute function public.tg_set_updated_at();
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'promotion_posts' and policyname = 'deny_all_promotion_posts'
  ) then
    create policy deny_all_promotion_posts
      on public.promotion_posts
      for all
      using (false)
      with check (false);
  end if;
end $$;

create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.promotion_feed_bonus(
  p_plan text,
  p_end_date timestamptz,
  p_boost_multiplier numeric default 1
)
returns integer
language plpgsql
immutable
as $$
declare
  v_days integer := greatest(0, ceil(extract(epoch from (coalesce(p_end_date, now()) - now())) / 86400.0)::integer);
  v_plan_weight integer := case lower(coalesce(p_plan, 'basic'))
    when 'premium' then 3
    when 'pro' then 2
    else 1
  end;
  v_multiplier numeric := greatest(coalesce(p_boost_multiplier, 1), 1);
begin
  return round(500 * v_days * v_plan_weight * v_multiplier)::integer;
end;
$$;

create or replace view public.active_content_promotions as
select
  p.id,
  coalesce(nullif(p.content_id, ''), nullif(p.target_id, '')) as content_id,
  coalesce(nullif(p.content_type, ''), 'song') as content_type,
  p.user_id,
  p.title,
  p.plan,
  p.status,
  coalesce(p.start_date, p.starts_at) as start_date,
  coalesce(p.end_date, p.ends_at) as end_date,
  p.featured_badge,
  p.feed_boost_multiplier,
  public.promotion_feed_bonus(p.plan, coalesce(p.end_date, p.ends_at), p.feed_boost_multiplier) + coalesce(p.promotion_score_bonus, 0) as promotion_bonus,
  p.facebook_page_url,
  p.instagram_url,
  p.x_url,
  p.whatsapp_channel_url,
  p.created_at,
  p.updated_at
from public.promotions p
where coalesce(nullif(p.content_id, ''), nullif(p.target_id, '')) is not null
  and coalesce(p.status, 'draft') = 'active'
  and coalesce(p.is_active, false) = true
  and coalesce(p.end_date, p.ends_at, now() + interval '1 day') >= now();

notify pgrst, 'reload schema';