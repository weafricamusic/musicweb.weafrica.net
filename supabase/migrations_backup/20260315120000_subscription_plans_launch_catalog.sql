-- Launch catalog refresh (March 2026)
-- Keep stable consumer backend IDs (`free`, `premium`, `platinum`),
-- while promoting artist_* and dj_* to first-class launch plan IDs.

alter table public.subscription_plans
  add column if not exists plan_id text,
  add column if not exists audience text,
  add column if not exists name text,
  add column if not exists price_mwk integer,
  add column if not exists billing_interval text,
  add column if not exists currency text,
  add column if not exists active boolean,
  add column if not exists is_active boolean,
  add column if not exists sort_order integer,
  add column if not exists features jsonb,
  add column if not exists perks jsonb,
  add column if not exists marketing jsonb,
  add column if not exists updated_at timestamptz default now();

update public.subscription_plans
set
  currency = coalesce(nullif(trim(currency), ''), 'MWK'),
  billing_interval = coalesce(nullif(trim(billing_interval), ''), 'month'),
  active = coalesce(active, is_active, true),
  is_active = coalesce(is_active, active, true),
  sort_order = coalesce(sort_order, 999),
  features = coalesce(features, '{}'::jsonb),
  perks = coalesce(perks, '{}'::jsonb),
  marketing = coalesce(marketing, '{}'::jsonb),
  updated_at = coalesce(updated_at, now())
where true;

do $$
declare
  c record;
begin
  for c in (
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'subscription_plans'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%audience%'
  ) loop
    execute format('alter table public.subscription_plans drop constraint if exists %I', c.conname);
  end loop;

  begin
    execute $sql$
      alter table public.subscription_plans
        add constraint subscription_plans_audience_launch_check
        check (audience is null or audience in ('consumer','creator','both','artist','dj'))
    $sql$;
  exception when duplicate_object then
    null;
  end;
end $$;

with launch_rows as (
  select *
  from jsonb_to_recordset(
    $$[
      {
        "plan_id": "free",
        "audience": "consumer",
        "name": "Free",
        "price_mwk": 0,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 10,
        "active": true,
        "is_active": true,
        "features": {
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "quality": {"audio": "low"},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "limited"}
        },
        "perks": {
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "quality": {"audio": "low"},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "limited"}
        },
        "marketing": {
          "tagline": "Start listening for free.",
          "bullets": [
            "Ad-supported streaming",
            "Standard audio quality",
            "No offline downloads"
          ]
        }
      },
      {
        "plan_id": "premium",
        "audience": "consumer",
        "name": "Premium Listener",
        "price_mwk": 4000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 20,
        "active": true,
        "is_active": true,
        "features": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "quality": {"audio": "high", "audio_max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "audio": {"max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "marketing": {
          "tagline": "Ad-free listening with offline access.",
          "bullets": [
            "No ads",
            "Offline downloads",
            "High quality audio up to 320 kbps",
            "Unlimited skips",
            "Create playlists"
          ]
        }
      },
      {
        "plan_id": "platinum",
        "audience": "consumer",
        "name": "VIP Listener",
        "price_mwk": 8500,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 30,
        "active": true,
        "is_active": true,
        "features": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": true},
          "quality": {"audio": "studio", "audio_max_kbps": 320},
          "content_access": "exclusive",
          "battles": {"priority": "priority"},
          "featured": true,
          "coins": {
            "monthly_free": {"amount": 200},
            "weekly_free": {"amount": 50}
          }
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": true},
          "quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "content_access": "exclusive",
          "battles": {"priority": "priority"},
          "featured": true,
          "coins": {
            "monthly_free": {"amount": 200},
            "weekly_free": {"amount": 50}
          }
        },
        "marketing": {
          "tagline": "Everything in Premium Listener plus VIP access.",
          "bullets": [
            "Everything in Premium Listener",
            "Studio-grade audio access",
            "Exclusive drops and early releases",
            "Priority access in live battles",
            "Playlist mixing tools"
          ]
        }
      },
      {
        "plan_id": "artist_starter",
        "audience": "artist",
        "name": "Artist Starter",
        "price_mwk": 0,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 110,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "artist",
            "tier": "starter",
            "uploads": {"tracks_per_month": 5},
            "analytics": "basic",
            "fan_club": false,
            "monetization": false,
            "manual_launch_offer": true
          },
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "limited"}
        },
        "perks": {
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "limited"}
        },
        "marketing": {
          "tagline": "Start building your artist profile.",
          "bullets": [
            "Creator starter access",
            "Basic analytics",
            "Manual Artist Pro launch offer eligible"
          ]
        }
      },
      {
        "plan_id": "artist_pro",
        "audience": "artist",
        "name": "Artist Pro",
        "price_mwk": 8000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 120,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "artist",
            "tier": "pro",
            "uploads": {"tracks_per_month": 25},
            "analytics": "advanced",
            "fan_club": true,
            "monetization": true,
            "manual_launch_offer": true
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "quality": {"audio": "high", "audio_max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "audio": {"max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "marketing": {
          "tagline": "Grow faster with monetization tools.",
          "bullets": [
            "Expanded upload capacity",
            "Advanced analytics",
            "Fan club and creator tools",
            "Manual 30-day launch offer supported"
          ]
        }
      },
      {
        "plan_id": "artist_premium",
        "audience": "artist",
        "name": "Artist Premium",
        "price_mwk": 12000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 130,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "artist",
            "tier": "premium",
            "uploads": {"tracks_per_month": "unlimited"},
            "analytics": "real_time",
            "fan_club": true,
            "monetization": true,
            "priority_support": true
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": true},
          "quality": {"audio": "studio", "audio_max_kbps": 320},
          "content_access": "exclusive",
          "battles": {"priority": "priority"},
          "featured": true
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": true},
          "quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "content_access": "exclusive",
          "battles": {"priority": "priority"},
          "featured": true
        },
        "marketing": {
          "tagline": "Top-tier artist access for scale.",
          "bullets": [
            "Everything in Artist Pro",
            "Highest creator limits",
            "Priority placement and support",
            "Premium creator tools"
          ]
        }
      },
      {
        "plan_id": "dj_starter",
        "audience": "dj",
        "name": "DJ Starter",
        "price_mwk": 0,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 210,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "dj",
            "tier": "starter",
            "uploads": {"sets_per_month": 5},
            "analytics": "basic",
            "monetization": false,
            "manual_launch_offer": true
          },
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "limited"}
        },
        "perks": {
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "limited"}
        },
        "marketing": {
          "tagline": "Start building your DJ presence.",
          "bullets": [
            "Starter DJ tools",
            "Basic analytics",
            "Manual DJ Pro launch offer eligible"
          ]
        }
      },
      {
        "plan_id": "dj_pro",
        "audience": "dj",
        "name": "DJ Pro",
        "price_mwk": 7000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 220,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "dj",
            "tier": "pro",
            "uploads": {"sets_per_month": 25},
            "analytics": "advanced",
            "monetization": true,
            "manual_launch_offer": true
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "quality": {"audio": "high", "audio_max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "audio": {"max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "marketing": {
          "tagline": "Unlock pro DJ growth tools.",
          "bullets": [
            "Expanded DJ creator access",
            "Advanced analytics",
            "Priority creator tools",
            "Manual 30-day launch offer supported"
          ]
        }
      },
      {
        "plan_id": "dj_premium",
        "audience": "dj",
        "name": "DJ Premium",
        "price_mwk": 11000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 230,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "dj",
            "tier": "premium",
            "uploads": {"sets_per_month": "unlimited"},
            "analytics": "real_time",
            "monetization": true,
            "priority_support": true
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": true},
          "quality": {"audio": "studio", "audio_max_kbps": 320},
          "content_access": "exclusive",
          "battles": {"priority": "priority"},
          "featured": true
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": true},
          "quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "content_access": "exclusive",
          "battles": {"priority": "priority"},
          "featured": true
        },
        "marketing": {
          "tagline": "Top-tier DJ access for scale.",
          "bullets": [
            "Everything in DJ Pro",
            "Highest DJ limits",
            "Premium placement and support",
            "Premium creator tools"
          ]
        }
      }
    ]$$::jsonb
  ) as rows(
    plan_id text,
    audience text,
    name text,
    price_mwk integer,
    billing_interval text,
    currency text,
    sort_order integer,
    active boolean,
    is_active boolean,
    features jsonb,
    perks jsonb,
    marketing jsonb
  )
),
updated as (
  update public.subscription_plans sp
  set
    audience = lr.audience,
    name = lr.name,
    price_mwk = lr.price_mwk,
    billing_interval = lr.billing_interval,
    currency = lr.currency,
    sort_order = lr.sort_order,
    active = lr.active,
    is_active = lr.is_active,
    features = lr.features,
    perks = lr.perks,
    marketing = lr.marketing,
    updated_at = now()
  from launch_rows lr
  where sp.plan_id = lr.plan_id
  returning sp.plan_id
)
insert into public.subscription_plans (
  plan_id,
  audience,
  name,
  price_mwk,
  billing_interval,
  currency,
  sort_order,
  active,
  is_active,
  features,
  perks,
  marketing,
  updated_at,
  role,
  plan,
  price
)
select
  lr.plan_id,
  lr.audience,
  lr.name,
  lr.price_mwk,
  lr.billing_interval,
  lr.currency,
  lr.sort_order,
  lr.active,
  lr.is_active,
  lr.features,
  lr.perks,
  lr.marketing,
  now(),
  case
    when lr.plan_id in ('artist_starter', 'artist_pro', 'artist_premium') then 'artist'
    when lr.plan_id in ('dj_starter', 'dj_pro', 'dj_premium') then 'dj'
    else 'consumer'
  end,
  lr.plan_id,
  lr.price_mwk
from launch_rows lr
on conflict (plan_id) do update set
  audience = excluded.audience,
  name = excluded.name,
  price_mwk = excluded.price_mwk,
  billing_interval = excluded.billing_interval,
  currency = excluded.currency,
  sort_order = excluded.sort_order,
  active = excluded.active,
  is_active = excluded.is_active,
  features = excluded.features,
  perks = excluded.perks,
  marketing = excluded.marketing,
  updated_at = excluded.updated_at,
  role = excluded.role,
  plan = excluded.plan,
  price = excluded.price;

update public.subscription_plans
set
  active = false,
  is_active = false,
  updated_at = now()
where plan_id in (
  'family',
  'vip',
  'starter',
  'pro',
  'elite',
  'artist_free',
  'dj_free',
  'artist_plus',
  'dj_plus',
  'premium_weekly',
  'platinum_weekly',
  'vip_weekly',
  'pro_weekly',
  'elite_weekly'
);

update public.subscription_plans
set
  active = false,
  is_active = false,
  updated_at = now()
where coalesce(lower(trim(billing_interval)), 'month') not in ('month', 'monthly')
  and plan_id not in (
    'free',
    'premium',
    'platinum',
    'artist_starter',
    'artist_pro',
    'artist_premium',
    'dj_starter',
    'dj_pro',
    'dj_premium'
  );

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'role'
  ) then
    update public.subscription_plans
    set role = case
      when plan_id in ('artist_starter', 'artist_pro', 'artist_premium') then 'artist'
      when plan_id in ('dj_starter', 'dj_pro', 'dj_premium') then 'dj'
      else 'consumer'
    end
    where plan_id in (
      'free',
      'premium',
      'platinum',
      'artist_starter',
      'artist_pro',
      'artist_premium',
      'dj_starter',
      'dj_pro',
      'dj_premium'
    );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'plan'
  ) then
    update public.subscription_plans
    set plan = plan_id
    where plan_id in (
      'free',
      'premium',
      'platinum',
      'artist_starter',
      'artist_pro',
      'artist_premium',
      'dj_starter',
      'dj_pro',
      'dj_premium'
    );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'price'
  ) then
    update public.subscription_plans
    set price = price_mwk
    where plan_id in (
      'free',
      'premium',
      'platinum',
      'artist_starter',
      'artist_pro',
      'artist_premium',
      'dj_starter',
      'dj_pro',
      'dj_premium'
    );
  end if;
end $$;

create index if not exists subscription_plans_launch_active_idx
  on public.subscription_plans (active, is_active, audience, sort_order);

notify pgrst, 'reload schema';
