-- Monetization catalog refresh (March 2026)
-- Persists the Free -> Premium -> Platinum ladder for consumer, artist, and DJ plans.

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
  add column if not exists updated_at timestamptz default now(),
  add column if not exists role text,
  add column if not exists plan text,
  add column if not exists price numeric;

-- Legacy schemas may include a plan_id whitelist check constraint.
-- Drop/replace it so we can seed creator plan_ids like artist_starter/dj_starter.
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
      and pg_get_constraintdef(con.oid) ilike '%plan_id%'
  ) loop
    execute format('alter table public.subscription_plans drop constraint if exists %I', c.conname);
  end loop;

  begin
    execute $sql$
      alter table public.subscription_plans
        add constraint subscription_plans_plan_id_monetization_check
        check (
          plan_id is null
          or lower(plan_id) in (
            'free', 'premium', 'platinum',
            'artist_starter', 'artist_pro', 'artist_premium',
            'dj_starter', 'dj_pro', 'dj_premium',
            'family', 'vip', 'starter', 'pro', 'elite',
            'artist_free', 'dj_free', 'artist_plus', 'dj_plus',
            'premium_weekly', 'platinum_weekly', 'vip_weekly', 'pro_weekly', 'elite_weekly'
          )
        )
    $sql$;
  exception when duplicate_object then
    null;
  end;
end $$;

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
        add constraint subscription_plans_audience_monetization_check
        check (audience is null or audience in ('consumer','creator','both','artist','dj'))
    $sql$;
  exception when duplicate_object then
    null;
  end;
end $$;

with monetization_rows as (
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
          "ads": {"enabled": true, "interstitial_every_songs": 2, "mode": "standard"},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "quality": {"audio": "standard", "audio_max_kbps": 128},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "analytics": {"level": "basic"},
          "visibility": {"boost": "none"}
        },
        "perks": {
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "playback": {"background_play": false},
          "downloads": {"enabled": false},
          "playlists": {"create": false, "mix": false},
          "quality": {"audio": "standard", "audio_max_kbps": 128},
          "content_access": "limited",
          "content_limit_ratio": 0.3,
          "battles": {"priority": "none"}
        },
        "marketing": {
          "tagline": "Start your journey for free.",
          "bullets": [
            "Ad-supported listening",
            "Standard audio quality",
            "Normal discovery ranking",
            "No offline downloads"
          ]
        }
      },
      {
        "plan_id": "premium",
        "audience": "consumer",
        "name": "Premium",
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
          "analytics": {"level": "standard"},
          "visibility": {"boost": "small"}
        },
        "perks": {
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "playback": {"background_play": true},
          "downloads": {"enabled": true},
          "playlists": {"create": true, "mix": false},
          "quality": {"audio": "high", "audio_max_kbps": 320},
          "content_access": "standard",
          "battles": {"priority": "standard"}
        },
        "marketing": {
          "tagline": "Unlock more features and fewer limits.",
          "bullets": [
            "Ad-free playback",
            "Offline downloads",
            "High quality audio up to 320 kbps",
            "Playlist creation and background play"
          ]
        }
      },
      {
        "plan_id": "platinum",
        "audience": "consumer",
        "name": "Platinum",
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
          "quality": {"audio": "studio", "audio_max_kbps": 320, "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "content_access": "exclusive",
          "analytics": {"level": "advanced"},
          "visibility": {"boost": "high"},
          "featured": true,
          "battles": {"priority": "priority"},
          "coins": {"monthly_free": {"amount": 200}}
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
          "coins": {"monthly_free": {"amount": 200}}
        },
        "marketing": {
          "tagline": "Go all-in with the full power tier.",
          "bullets": [
            "Everything in Premium",
            "Studio-grade audio and playlist mixing",
            "Exclusive drops and priority access",
            "Highest visibility and member perks"
          ]
        }
      },
      {
        "plan_id": "artist_starter",
        "audience": "artist",
        "name": "Artist Free",
        "price_mwk": 0,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 110,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "artist",
            "tier": "free",
            "uploads": {"songs": 10, "videos": 3, "bulk_upload": false},
            "quality": {"audio": "standard", "video": "standard"},
            "analytics": {"level": "basic", "views": true, "likes": true, "comments": false, "revenue": false, "watch_time": false, "countries": false},
            "monetization": {"streams": false, "coins": false, "live": false, "battles": false, "fan_support": false},
            "withdrawals": {"access": "none"},
            "live": {"host": false, "battles": false, "multi_guest": false},
            "visibility": {"boost": "none", "featured_sections": []},
            "profile": {"customization": false, "verified_badge": false, "pin_content": false},
            "marketing": {"promote_content": false, "push_to_fans": false},
            "ads_on_content": "full"
          },
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "battles": {"enabled": false, "priority": "none"},
          "content_access": "limited",
          "content_limit_ratio": 0.3
        },
        "perks": {
          "creator": {
            "type": "artist",
            "uploads": {"songs": 10, "videos": 3},
            "monetization": {"enabled": false},
            "withdrawals": {"access": "none"},
            "live": {"enabled": false},
            "visibility": {"boost": "none"},
            "profile": {"customization": false, "verified_badge": false}
          },
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "battles": {"priority": "none"}
        },
        "marketing": {
          "tagline": "Start your journey and test the platform.",
          "bullets": [
            "Upload up to 10 songs and 3 videos",
            "Basic analytics: views and likes",
            "No live streaming or coin earnings",
            "Normal feed ranking with ads on content"
          ]
        }
      },
      {
        "plan_id": "artist_pro",
        "audience": "artist",
        "name": "Artist Premium",
        "price_mwk": 8000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 120,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "artist",
            "tier": "premium",
            "uploads": {"songs": -1, "videos": 10, "bulk_upload": false},
            "quality": {"audio": "high", "video": "hd"},
            "analytics": {"level": "medium", "views": true, "likes": true, "comments": true, "revenue": true, "watch_time": false, "countries": false},
            "monetization": {"streams": true, "coins": true, "live": true, "battles": false, "fan_support": false},
            "withdrawals": {"access": "limited"},
            "live": {"host": true, "battles": false, "multi_guest": false},
            "visibility": {"boost": "small", "featured_sections": []},
            "profile": {"customization": true, "verified_badge": false, "pin_content": false},
            "marketing": {"promote_content": false, "push_to_fans": false},
            "ads_on_content": "reduced"
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "battles": {"enabled": false, "priority": "none"},
          "content_access": "standard",
          "quality": {"audio": "high", "audio_max_kbps": 320}
        },
        "perks": {
          "creator": {
            "type": "artist",
            "uploads": {"songs": "unlimited", "videos": 10},
            "monetization": {"streams": true, "coins": true},
            "withdrawals": {"access": "limited"},
            "live": {"enabled": true},
            "visibility": {"boost": "small"},
            "profile": {"customization": true, "verified_badge": false}
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "quality": {"audio": "high", "audio_max_kbps": 320},
          "battles": {"priority": "none"}
        },
        "marketing": {
          "tagline": "Unlock more features and start earning.",
          "bullets": [
            "Unlimited songs and more video uploads",
            "Go live and earn from streams and coins",
            "Comments analytics and a small feed boost",
            "Withdrawals available with limits"
          ]
        }
      },
      {
        "plan_id": "artist_premium",
        "audience": "artist",
        "name": "Artist Platinum",
        "price_mwk": 12000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 130,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "artist",
            "tier": "platinum",
            "uploads": {"songs": -1, "videos": -1, "bulk_upload": true},
            "quality": {"audio": "studio", "video": "hd"},
            "analytics": {"level": "advanced", "views": true, "likes": true, "comments": true, "revenue": true, "watch_time": true, "countries": true},
            "monetization": {"streams": true, "coins": true, "live": true, "battles": true, "fan_support": true},
            "withdrawals": {"access": "unlimited"},
            "live": {"host": true, "battles": true, "multi_guest": true},
            "visibility": {"boost": "high", "featured_sections": ["trending", "recommended", "top_artists"]},
            "profile": {"customization": true, "verified_badge": true, "pin_content": true},
            "marketing": {"promote_content": true, "push_to_fans": true},
            "ads_on_content": "none"
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "battles": {"enabled": true, "priority": "priority"},
          "content_access": "exclusive",
          "quality": {"audio": "studio", "audio_max_kbps": 320, "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "featured": true
        },
        "perks": {
          "creator": {
            "type": "artist",
            "uploads": {"songs": "unlimited", "videos": "unlimited", "bulk_upload": true},
            "monetization": {"streams": true, "coins": true, "live": true, "battles": true, "fan_support": true},
            "withdrawals": {"access": "unlimited"},
            "live": {"enabled": true, "battles": true, "multi_guest": true},
            "visibility": {"boost": "high"},
            "profile": {"customization": true, "verified_badge": true, "pin_content": true},
            "marketing": {"promote_content": true, "push_to_fans": true}
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "battles": {"priority": "priority"},
          "featured": true
        },
        "marketing": {
          "tagline": "Go viral, earn more, and own the spotlight.",
          "bullets": [
            "Unlimited high-quality uploads plus bulk upload",
            "Battles, multi-guest live, and full earnings",
            "Advanced analytics with revenue and country insights",
            "Verified badge, fan push, promotions, and no ads"
          ]
        }
      },
      {
        "plan_id": "dj_starter",
        "audience": "dj",
        "name": "DJ Free",
        "price_mwk": 0,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 210,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "dj",
            "tier": "free",
            "uploads": {"mixes": 5, "bulk_upload": false},
            "analytics": {"level": "basic", "views": true, "likes": true, "comments": false, "revenue": false},
            "monetization": {"live_gifts": false, "battles": false, "streams": false},
            "withdrawals": {"access": "none"},
            "live": {"host": false, "battles": false},
            "visibility": {"boost": "none", "featured_sections": []},
            "profile": {"customization": false, "verified_badge": false},
            "ads_on_content": "full"
          },
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "battles": {"enabled": false, "priority": "none"},
          "content_access": "limited",
          "content_limit_ratio": 0.3
        },
        "perks": {
          "creator": {
            "type": "dj",
            "uploads": {"mixes": 5},
            "monetization": {"enabled": false},
            "withdrawals": {"access": "none"},
            "live": {"enabled": false},
            "visibility": {"boost": "none"},
            "profile": {"customization": false, "verified_badge": false}
          },
          "ads": {"enabled": true, "interstitial_every_songs": 2},
          "battles": {"priority": "none"}
        },
        "marketing": {
          "tagline": "Test the platform before you upgrade.",
          "bullets": [
            "Upload limited mixes",
            "Basic stats only",
            "No live DJ streaming or battles",
            "No monetization or withdrawals"
          ]
        }
      },
      {
        "plan_id": "dj_pro",
        "audience": "dj",
        "name": "DJ Premium",
        "price_mwk": 7000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 220,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "dj",
            "tier": "premium",
            "uploads": {"mixes": -1, "bulk_upload": false},
            "analytics": {"level": "medium", "views": true, "likes": true, "comments": true, "revenue": true},
            "monetization": {"live_gifts": true, "battles": false, "streams": true},
            "withdrawals": {"access": "limited"},
            "live": {"host": true, "battles": false},
            "visibility": {"boost": "small", "featured_sections": []},
            "profile": {"customization": true, "verified_badge": false},
            "ads_on_content": "reduced"
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "battles": {"enabled": false, "priority": "none"},
          "content_access": "standard",
          "quality": {"audio": "high", "audio_max_kbps": 320}
        },
        "perks": {
          "creator": {
            "type": "dj",
            "uploads": {"mixes": "unlimited"},
            "monetization": {"live_gifts": true, "streams": true},
            "withdrawals": {"access": "limited"},
            "live": {"enabled": true},
            "visibility": {"boost": "small"},
            "profile": {"customization": true, "verified_badge": false}
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "quality": {"audio": "high", "audio_max_kbps": 320},
          "battles": {"priority": "none"}
        },
        "marketing": {
          "tagline": "Go live and start earning from your sets.",
          "bullets": [
            "Unlimited mixes and live DJ sets",
            "Earn from live gifts",
            "Medium analytics with a small visibility boost",
            "Withdrawals available with limits"
          ]
        }
      },
      {
        "plan_id": "dj_premium",
        "audience": "dj",
        "name": "DJ Platinum",
        "price_mwk": 11000,
        "billing_interval": "month",
        "currency": "MWK",
        "sort_order": 230,
        "active": true,
        "is_active": true,
        "features": {
          "creator": {
            "audience": "dj",
            "tier": "platinum",
            "uploads": {"mixes": -1, "bulk_upload": true},
            "analytics": {"level": "advanced", "views": true, "likes": true, "comments": true, "revenue": true, "watch_time": true, "countries": true},
            "monetization": {"live_gifts": true, "battles": true, "streams": true, "fan_support": true},
            "withdrawals": {"access": "unlimited"},
            "live": {"host": true, "battles": true, "audience_voting": true, "rewards": true},
            "visibility": {"boost": "high", "featured_sections": ["live_now", "top_djs"]},
            "profile": {"customization": true, "verified_badge": true, "pin_content": true},
            "ads_on_content": "none"
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "battles": {"enabled": true, "priority": "priority"},
          "content_access": "exclusive",
          "quality": {"audio": "studio", "audio_max_kbps": 320, "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "featured": true
        },
        "perks": {
          "creator": {
            "type": "dj",
            "uploads": {"mixes": "unlimited", "bulk_upload": true},
            "monetization": {"live_gifts": true, "battles": true, "streams": true, "fan_support": true},
            "withdrawals": {"access": "unlimited"},
            "live": {"enabled": true, "battles": true, "audience_voting": true, "rewards": true},
            "visibility": {"boost": "high"},
            "profile": {"customization": true, "verified_badge": true, "pin_content": true}
          },
          "ads": {"enabled": false, "interstitial_every_songs": 0},
          "quality": {"audio": "studio", "audio_max_bit_depth": 24, "audio_max_sample_rate_khz": 44.1},
          "battles": {"priority": "priority"},
          "featured": true
        },
        "marketing": {
          "tagline": "Unlock battles, earnings, and the spotlight.",
          "bullets": [
            "Unlimited mixes and premium live DJ sets",
            "DJ battles with audience voting and rewards",
            "Full earnings with unlimited withdrawals",
            "Featured placement, verified badge, and custom DJ branding"
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
    audience = mr.audience,
    name = mr.name,
    price_mwk = mr.price_mwk,
    billing_interval = mr.billing_interval,
    currency = mr.currency,
    sort_order = mr.sort_order,
    active = mr.active,
    is_active = mr.is_active,
    features = mr.features,
    perks = mr.perks,
    marketing = mr.marketing,
    updated_at = now()
  from monetization_rows mr
  where sp.plan_id = mr.plan_id
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
  mr.plan_id,
  mr.audience,
  mr.name,
  mr.price_mwk,
  mr.billing_interval,
  mr.currency,
  mr.sort_order,
  mr.active,
  mr.is_active,
  mr.features,
  mr.perks,
  mr.marketing,
  now(),
  case
    when mr.plan_id in ('artist_starter', 'artist_pro', 'artist_premium') then 'artist'
    when mr.plan_id in ('dj_starter', 'dj_pro', 'dj_premium') then 'dj'
    else 'consumer'
  end,
  mr.plan_id,
  mr.price_mwk
from monetization_rows mr
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

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'role'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'plan'
  ) then
    -- Legacy deployments may contain duplicate consumer rows keyed by (role, plan) with NULL plan_id.
    -- Normalize these to a legacy namespace to avoid violating unique(role, plan, billing_interval)
    -- when we set role/plan for the canonical plan_id rows.
    update public.subscription_plans
    set
      role = 'legacy_consumer',
      plan = 'legacy_' || plan,
      is_active = false,
      active = false,
      updated_at = now()
    where plan_id is null
      and role = 'consumer'
      and plan in ('free', 'premium', 'platinum');
  end if;

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
      'free', 'premium', 'platinum',
      'artist_starter', 'artist_pro', 'artist_premium',
      'dj_starter', 'dj_pro', 'dj_premium'
    );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'plan'
  ) then
    update public.subscription_plans
    set plan = plan_id
    where plan_id in (
      'free', 'premium', 'platinum',
      'artist_starter', 'artist_pro', 'artist_premium',
      'dj_starter', 'dj_pro', 'dj_premium'
    );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'subscription_plans' and column_name = 'price'
  ) then
    update public.subscription_plans
    set price = price_mwk
    where plan_id in (
      'free', 'premium', 'platinum',
      'artist_starter', 'artist_pro', 'artist_premium',
      'dj_starter', 'dj_pro', 'dj_premium'
    );
  end if;
end $$;

create index if not exists subscription_plans_monetization_idx
  on public.subscription_plans (active, is_active, audience, sort_order);

notify pgrst, 'reload schema';