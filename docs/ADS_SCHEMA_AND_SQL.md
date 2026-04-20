# Ads schema + SQL (Supabase)

This repo has **two** ad-related schemas in migrations:

- **Audio ads (current app flow)**: `ads` + tracking `ads_impressions` / `ads_clicks` / `ads_completions`
  - Fetch + tracking is implemented via Edge endpoints:
    - `GET /api/ads/next?placement=interstitial`
    - `POST /api/ads/track` with `{ ad_id, event }`
  - Tracking tables have RLS enabled and are intended to be written by the Edge **service role**.
  - The client also supports **video interstitials** when the ad payload includes `video_url`.
    - `video_url` is not part of the base migrations yet; if you add it to `public.ads`, the Edge handler will return it automatically.

- **Legacy ads**: `advertisements` + tracking `ad_impressions` / `ad_clicks`
  - These tables have RLS policies allowing authenticated inserts (see `005_ad_rls_and_audit.sql`).
  - Not currently used by the Flutter ads module.

## Verify tables/columns

```sql
-- What columns exist?
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'ads',
    'ads_impressions',
    'ads_clicks',
    'ads_completions',
    'advertisements',
    'ad_impressions',
    'ad_clicks'
  )
order by table_name, ordinal_position;

-- Check which tables have RLS enabled
select c.relname as table_name,
       c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'ads',
    'ads_impressions',
    'ads_clicks',
    'ads_completions',
    'advertisements',
    'ad_impressions',
    'ad_clicks'
  )
order by c.relname;

-- Show policies (if any)
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'ads',
    'ads_impressions',
    'ads_clicks',
    'ads_completions',
    'advertisements',
    'ad_impressions',
    'ad_clicks'
  )
order by tablename, policyname;
```

## Sample inserts (audio ads)

`public.ads.id` is `serial` in this repo (integer). Do **not** insert UUID ids.

```sql
-- Insert an audio interstitial ad
-- Note: older migrations created name/ad_unit_id as NOT NULL, but
-- 20260307160000_audio_ads_interstitials.sql relaxes those constraints.
insert into public.ads (
  name,
  ad_unit_id,
  placement,
  is_active,
  title,
  advertiser,
  audio_url,
  -- Optional: if you add this column in your DB
  -- video_url,
  image_url,
  click_url,
  duration_seconds,
  is_skippable,
  priority
) values (
  'Audio Interstitial Test',
  'audio_interstitial_test_001',
  'interstitial',
  true,
  'Sponsored: New Single Out Now',
  'WeAfrica Music',
  'https://YOUR-CDN/ads/audio/test.mp3',
  -- 'https://YOUR-CDN/ads/video/test.mp4',
  'https://YOUR-CDN/ads/images/test.jpg',
  'https://weafrica.example/landing',
  20,
  true,
  100
);
```

Tracking rows for audio ads are written via Edge (`/api/ads/track`) because the
`ads_*` tables have RLS enabled without client insert policies.

## Sample inserts (legacy advertisements)

```sql
-- Insert a legacy banner/video/etc ad (schema depends on 004_create_advertisements.sql)
select * from public.advertisements limit 1;
```
