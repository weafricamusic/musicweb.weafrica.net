-- Add optional video_url to ads for video interstitial support

alter table public.ads
  add column if not exists video_url text;

-- Optional helper index for active video ads.
create index if not exists ads_video_active_idx
  on public.ads (priority desc, created_at desc)
  where is_active = true and video_url is not null;
