-- Four-structure subscription blueprint alignment (March 2026)
-- Ensures DB-backed subscription_plans matches the consumer/artist/dj blueprint.

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
  add column if not exists trial_eligible boolean not null default false,
  add column if not exists trial_duration_days integer not null default 0,
  add column if not exists updated_at timestamptz default now();

update public.subscription_plans
set
  audience = 'consumer',
  name = 'Free',
  price_mwk = 0,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 10,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'ads', jsonb_build_object('enabled', true, 'interstitial_every_songs', 2),
    'playback', jsonb_build_object('background_play', false, 'skips_per_hour', 6),
    'downloads', jsonb_build_object('enabled', false, 'video_enabled', false),
    'quality', jsonb_build_object('audio', 'standard', 'audio_max_kbps', 128),
    'gifting', jsonb_build_object('tier', 'limited'),
    'live', jsonb_build_object('access', 'watch_only', 'song_requests', jsonb_build_object('enabled', false), 'highlighted_comments', false),
    'content', jsonb_build_object('exclusive', false, 'early_access', false),
    'content_access', 'limited',
    'tickets', jsonb_build_object(
      'buy', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard')),
      'priority_booking', false,
      'redeem_bonus_coins', false
    ),
    'monthly_bonus_coins', 0
  ),
  perks = jsonb_build_object(
    'ads', jsonb_build_object('enabled', true, 'interstitial_every_songs', 2),
    'playback', jsonb_build_object('background_play', false, 'skips_per_hour', 6),
    'downloads', jsonb_build_object('enabled', false, 'video_enabled', false),
    'quality', jsonb_build_object('audio', 'standard', 'audio_max_kbps', 128),
    'gifting', jsonb_build_object('tier', 'limited'),
    'live', jsonb_build_object('access', 'watch_only', 'song_requests', jsonb_build_object('enabled', false), 'highlighted_comments', false),
    'content', jsonb_build_object('exclusive', false, 'early_access', false),
    'content_access', 'limited',
    'tickets', jsonb_build_object(
      'buy', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard')),
      'priority_booking', false,
      'redeem_bonus_coins', false
    ),
    'monthly_bonus_coins', 0
  ),
  marketing = jsonb_build_object(
    'tagline', 'Discover new music for free with light limits.',
    'bullets', jsonb_build_array(
      'Ad-supported listening with limited skips',
      'Standard audio quality and no background play',
      'No audio or video downloads',
      'Light fan gifts (coin top-ups available separately)'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'free';

update public.subscription_plans
set
  audience = 'consumer',
  name = 'Premium',
  price_mwk = 4000,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 20,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'ads', jsonb_build_object('enabled', false, 'interstitial_every_songs', 0),
    'playback', jsonb_build_object('background_play', true, 'skips_per_hour', -1),
    'downloads', jsonb_build_object('enabled', true, 'video_enabled', false),
    'quality', jsonb_build_object('audio', 'high', 'audio_max_kbps', 320),
    'gifting', jsonb_build_object('tier', 'standard'),
    'live', jsonb_build_object('access', 'standard', 'song_requests', jsonb_build_object('enabled', false), 'highlighted_comments', false),
    'content', jsonb_build_object('exclusive', false, 'early_access', true),
    'content_access', 'standard',
    'tickets', jsonb_build_object(
      'buy', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip')),
      'priority_booking', false,
      'redeem_bonus_coins', false
    ),
    'monthly_bonus_coins', 0
  ),
  perks = jsonb_build_object(
    'ads', jsonb_build_object('enabled', false, 'interstitial_every_songs', 0),
    'playback', jsonb_build_object('background_play', true, 'skips_per_hour', -1),
    'downloads', jsonb_build_object('enabled', true, 'video_enabled', false),
    'quality', jsonb_build_object('audio', 'high', 'audio_max_kbps', 320),
    'gifting', jsonb_build_object('tier', 'standard'),
    'live', jsonb_build_object('access', 'standard', 'song_requests', jsonb_build_object('enabled', false), 'highlighted_comments', false),
    'content', jsonb_build_object('exclusive', false, 'early_access', true),
    'content_access', 'standard',
    'tickets', jsonb_build_object(
      'buy', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip')),
      'priority_booking', false,
      'redeem_bonus_coins', false
    ),
    'monthly_bonus_coins', 0
  ),
  marketing = jsonb_build_object(
    'tagline', 'Freedom tier: no ads, downloads, and full listening control.',
    'bullets', jsonb_build_array(
      'Ad-free playback',
      'Unlimited skips, background play, and offline audio downloads',
      'High quality audio up to 320 kbps',
      'Standard gift catalog for stronger fan support',
      'Limited early access to select drops'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'premium';

update public.subscription_plans
set
  audience = 'consumer',
  name = 'Platinum',
  price_mwk = 8500,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 30,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'ads', jsonb_build_object('enabled', false, 'interstitial_every_songs', 0),
    'playback', jsonb_build_object('background_play', true, 'skips_per_hour', -1),
    'downloads', jsonb_build_object('enabled', true, 'video_enabled', true),
    'quality', jsonb_build_object('audio', 'studio', 'audio_max_kbps', 320, 'audio_max_bit_depth', 24, 'audio_max_sample_rate_khz', 44.1),
    'gifting', jsonb_build_object('tier', 'vip'),
    'live', jsonb_build_object('access', 'priority', 'song_requests', jsonb_build_object('enabled', true), 'highlighted_comments', true),
    'content', jsonb_build_object('exclusive', true, 'early_access', true),
    'content_access', 'exclusive',
    'tickets', jsonb_build_object(
      'buy', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip', 'priority')),
      'priority_booking', true,
      'redeem_bonus_coins', true
    ),
    'coins', jsonb_build_object('monthly_bonus', jsonb_build_object('amount', 200)),
    'monthly_bonus_coins', 200,
    'vip_badge', true
  ),
  perks = jsonb_build_object(
    'ads', jsonb_build_object('enabled', false, 'interstitial_every_songs', 0),
    'playback', jsonb_build_object('background_play', true, 'skips_per_hour', -1),
    'downloads', jsonb_build_object('enabled', true, 'video_enabled', true),
    'quality', jsonb_build_object('audio', 'studio', 'audio_max_bit_depth', 24, 'audio_max_sample_rate_khz', 44.1),
    'gifting', jsonb_build_object('tier', 'vip'),
    'live', jsonb_build_object('access', 'priority', 'song_requests', jsonb_build_object('enabled', true), 'highlighted_comments', true),
    'content', jsonb_build_object('exclusive', true, 'early_access', true),
    'content_access', 'exclusive',
    'tickets', jsonb_build_object(
      'buy', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip', 'priority')),
      'priority_booking', true,
      'redeem_bonus_coins', true
    ),
    'coins', jsonb_build_object('monthly_bonus', jsonb_build_object('amount', 200)),
    'monthly_bonus_coins', 200,
    'recognition', jsonb_build_object('vip_badge', true)
  ),
  marketing = jsonb_build_object(
    'tagline', 'Status tier: VIP fan power in every live room.',
    'bullets', jsonb_build_array(
      'Everything in Premium',
      'Priority live access, VIP gifts, and highlighted comments',
      'Song requests, exclusive drops, and full early access',
      '200 monthly bonus coins and the VIP badge'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'platinum';

update public.subscription_plans
set
  audience = 'artist',
  name = 'Artist Free',
  price_mwk = 0,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 110,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'creator', jsonb_build_object(
      'audience', 'artist',
      'tier', 'free',
      'uploads', jsonb_build_object('songs', 5, 'videos', 0, 'bulk_upload', false),
      'analytics', jsonb_build_object('level', 'basic', 'views', true, 'likes', true, 'comments', false),
      'monetization', jsonb_build_object('streams', false, 'coins', false, 'live', false, 'battles', false),
      'live', jsonb_build_object('host', false, 'battles', false),
      'withdrawals', jsonb_build_object('access', 'none')
    ),
    'battles', jsonb_build_object('enabled', false, 'priority', 'none'),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', false, 'tiers', jsonb_build_array()))
  ),
  perks = jsonb_build_object(
    'creator', jsonb_build_object('type', 'artist', 'uploads', jsonb_build_object('songs', 5, 'videos', 0)),
    'battles', jsonb_build_object('priority', 'none'),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', false, 'tiers', jsonb_build_array()))
  ),
  marketing = jsonb_build_object(
    'tagline', 'Start as an artist and build traction before monetizing.',
    'bullets', jsonb_build_array(
      'Upload up to 5 songs per month',
      'Basic analytics: plays and likes',
      'Watch live battles but cannot host yet',
      'Comments-only fan engagement and no ticket selling'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'artist_starter';

update public.subscription_plans
set
  audience = 'artist',
  name = 'Artist Premium',
  price_mwk = 6000,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 120,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'creator', jsonb_build_object(
      'audience', 'artist',
      'tier', 'premium',
      'uploads', jsonb_build_object('songs', 20, 'videos', 5, 'bulk_upload', false),
      'analytics', jsonb_build_object('level', 'medium', 'views', true, 'likes', true, 'comments', true, 'revenue', true),
      'monetization', jsonb_build_object('streams', true, 'coins', true, 'live', true, 'battles', true),
      'live', jsonb_build_object('host', true, 'battles', true),
      'withdrawals', jsonb_build_object('access', 'limited')
    ),
    'battles', jsonb_build_object('enabled', true, 'priority', 'standard'),
    'content', jsonb_build_object('exclusive', false, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard')))
  ),
  perks = jsonb_build_object(
    'creator', jsonb_build_object('type', 'artist', 'uploads', jsonb_build_object('songs', 20, 'videos', 5)),
    'battles', jsonb_build_object('priority', 'standard'),
    'content', jsonb_build_object('exclusive', false, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard')))
  ),
  marketing = jsonb_build_object(
    'tagline', 'Growth tier for active artists with moderate monetization.',
    'bullets', jsonb_build_array(
      'Upload up to 20 songs per month',
      'Join standard live battles and earn from gifts/coins',
      'Detailed audience analytics with moderate monetization',
      'Sell tickets for standard events'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'artist_pro';

update public.subscription_plans
set
  audience = 'artist',
  name = 'Artist Platinum',
  price_mwk = 12500,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 130,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'creator', jsonb_build_object(
      'audience', 'artist',
      'tier', 'platinum',
      'uploads', jsonb_build_object('songs', -1, 'videos', -1, 'bulk_upload', true),
      'analytics', jsonb_build_object('level', 'advanced', 'views', true, 'likes', true, 'comments', true, 'revenue', true, 'watch_time', true, 'countries', true),
      'monetization', jsonb_build_object('streams', true, 'coins', true, 'live', true, 'battles', true, 'fan_support', true),
      'live', jsonb_build_object('host', true, 'battles', true, 'multi_guest', true, 'song_requests', true),
      'withdrawals', jsonb_build_object('access', 'unlimited')
    ),
    'battles', jsonb_build_object('enabled', true, 'priority', 'priority'),
    'content', jsonb_build_object('exclusive', true, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip', 'priority'))),
    'monthly_bonus_coins', 200,
    'vip_badge', true
  ),
  perks = jsonb_build_object(
    'creator', jsonb_build_object('type', 'artist', 'uploads', jsonb_build_object('songs', 'unlimited', 'videos', 'unlimited', 'bulk_upload', true)),
    'battles', jsonb_build_object('priority', 'priority'),
    'content', jsonb_build_object('exclusive', true, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip', 'priority'))),
    'monthly_bonus_coins', 200
  ),
  marketing = jsonb_build_object(
    'tagline', 'Full artist power for VIP battles, events, and monetization.',
    'bullets', jsonb_build_array(
      'Unlimited high-quality uploads plus bulk upload',
      'Battles, multi-guest live, and full earnings',
      'Advanced analytics with revenue and country insights',
      'Sell VIP and priority ticketed events with top promotion'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'artist_premium';

update public.subscription_plans
set
  audience = 'dj',
  name = 'DJ Free',
  price_mwk = 0,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 210,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'creator', jsonb_build_object(
      'audience', 'dj',
      'tier', 'free',
      'uploads', jsonb_build_object('mixes', 5, 'bulk_upload', false),
      'analytics', jsonb_build_object('level', 'basic', 'views', true, 'watch_time', true),
      'monetization', jsonb_build_object('live_gifts', false, 'battles', false, 'streams', false),
      'live', jsonb_build_object('host', false, 'battles', false),
      'withdrawals', jsonb_build_object('access', 'none')
    ),
    'battles', jsonb_build_object('enabled', false, 'priority', 'none'),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', false, 'tiers', jsonb_build_array()))
  ),
  perks = jsonb_build_object(
    'creator', jsonb_build_object('type', 'dj', 'uploads', jsonb_build_object('mixes', 5)),
    'battles', jsonb_build_object('priority', 'none'),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', false, 'tiers', jsonb_build_array()))
  ),
  marketing = jsonb_build_object(
    'tagline', 'Start as a DJ and learn what your crowd responds to.',
    'bullets', jsonb_build_array(
      'Upload limited mixes',
      'Basic stats only',
      'Watch battles but cannot host yet',
      'No monetization, VIP badge, or ticket hosting'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'dj_starter';

update public.subscription_plans
set
  audience = 'dj',
  name = 'DJ Premium',
  price_mwk = 8000,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 220,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'creator', jsonb_build_object(
      'audience', 'dj',
      'tier', 'premium',
      'uploads', jsonb_build_object('mixes', -1, 'bulk_upload', false),
      'analytics', jsonb_build_object('level', 'medium', 'views', true, 'likes', true, 'comments', true, 'revenue', true),
      'monetization', jsonb_build_object('live_gifts', true, 'battles', true, 'streams', true),
      'live', jsonb_build_object('host', true, 'battles', true),
      'withdrawals', jsonb_build_object('access', 'limited')
    ),
    'battles', jsonb_build_object('enabled', true, 'priority', 'standard'),
    'content', jsonb_build_object('exclusive', false, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard')))
  ),
  perks = jsonb_build_object(
    'creator', jsonb_build_object('type', 'dj', 'uploads', jsonb_build_object('mixes', 'unlimited')),
    'battles', jsonb_build_object('priority', 'standard'),
    'content', jsonb_build_object('exclusive', false, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard')))
  ),
  marketing = jsonb_build_object(
    'tagline', 'Host standard battles and paid events with better insights.',
    'bullets', jsonb_build_array(
      'Host standard battles and live DJ sets',
      'Moderate analytics with audience and engagement trends',
      'Partial coin earnings and standard gift monetization',
      'Host standard paid events and concerts'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'dj_pro';

update public.subscription_plans
set
  audience = 'dj',
  name = 'DJ Platinum',
  price_mwk = 15000,
  billing_interval = 'month',
  currency = 'MWK',
  sort_order = 230,
  active = true,
  is_active = true,
  features = jsonb_build_object(
    'creator', jsonb_build_object(
      'audience', 'dj',
      'tier', 'platinum',
      'uploads', jsonb_build_object('mixes', -1, 'bulk_upload', true),
      'analytics', jsonb_build_object('level', 'advanced', 'views', true, 'likes', true, 'comments', true, 'revenue', true, 'watch_time', true, 'countries', true),
      'monetization', jsonb_build_object('live_gifts', true, 'battles', true, 'streams', true, 'fan_support', true),
      'live', jsonb_build_object('host', true, 'battles', true, 'audience_voting', true, 'rewards', true, 'song_requests', true, 'highlighted_comments', true, 'polls', true),
      'withdrawals', jsonb_build_object('access', 'unlimited')
    ),
    'battles', jsonb_build_object('enabled', true, 'priority', 'priority'),
    'content', jsonb_build_object('exclusive', true, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip', 'priority'))),
    'monthly_bonus_coins', 200,
    'vip_badge', true
  ),
  perks = jsonb_build_object(
    'creator', jsonb_build_object('type', 'dj', 'uploads', jsonb_build_object('mixes', 'unlimited', 'bulk_upload', true)),
    'battles', jsonb_build_object('priority', 'priority'),
    'content', jsonb_build_object('exclusive', true, 'early_access', true),
    'tickets', jsonb_build_object('sell', jsonb_build_object('enabled', true, 'tiers', jsonb_build_array('standard', 'vip', 'priority'))),
    'monthly_bonus_coins', 200
  ),
  marketing = jsonb_build_object(
    'tagline', 'Elite DJ tier for VIP battles, events, and full crowd control.',
    'bullets', jsonb_build_array(
      'Create and schedule VIP/priority battles and events',
      'Full analytics with top fans and live battle performance',
      'Full monetization with VIP gifts, coins, and ad revenue share',
      'Maximum visibility, VIP badge, and exclusive hosting rights'
    )
  ),
  updated_at = now()
where lower(coalesce(plan_id, '')) = 'dj_premium';

update public.subscription_plans
set
  trial_eligible = case
    when lower(coalesce(plan_id, '')) in ('artist_starter', 'dj_starter') then true
    else false
  end,
  trial_duration_days = case
    when lower(coalesce(plan_id, '')) in ('artist_starter', 'dj_starter') then 30
    else 0
  end,
  updated_at = now()
where lower(coalesce(plan_id, '')) in (
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

-- Optional event tier metadata for ticketing gates (keeps old schemas compatible).
alter table public.events
  add column if not exists access_tier text;

update public.events
set access_tier = coalesce(nullif(trim(access_tier), ''), 'standard')
where true;

create index if not exists events_access_tier_idx on public.events (access_tier);
