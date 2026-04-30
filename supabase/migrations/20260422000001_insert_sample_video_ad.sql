-- Insert sample video ad for testing
INSERT INTO public.ads (
  title,
  audio_url,
  video_url,
  duration_seconds,
  is_active,
  image_url,
  advertiser,
  click_url,
  is_skippable,
  priority
) VALUES (
  'WeAfrica Music - Discover African Beats',
  'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/ad_videos/2025-12-16-040541373_small.mp4',
  'https://nxkutpjdoidfwpkjbwcm.supabase.co/storage/v1/object/public/ad_videos/2025-12-16-040541373_small.mp4',
  30, -- Estimated duration (update if you know exact duration)
  true,
  NULL, -- No image for this ad
  'WeAfrica Music',
  NULL, -- No click URL
  false, -- Not skippable
  10 -- High priority to ensure it shows
)
ON CONFLICT DO NOTHING; -- In case this ad already exists

-- Verify the ad was inserted
SELECT 
  id,
  title,
  video_url,
  duration_seconds,
  is_active,
  priority
FROM public.ads
WHERE video_url LIKE '%2025-12-16-040541373_small.mp4%'
ORDER BY priority DESC, created_at DESC
LIMIT 1;