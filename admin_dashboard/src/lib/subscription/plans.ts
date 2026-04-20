export type SubscriptionPlanId = string

export type SubscriptionAnalyticsLevel = 'basic' | 'standard' | 'advanced'
export type SubscriptionBattlePriority = 'none' | 'standard' | 'priority'
export type SubscriptionContentAccess = 'limited' | 'standard' | 'exclusive'

export type SubscriptionEntitlements = {
  plan_id: SubscriptionPlanId
  name: string
  price_mwk: number
  billing_interval: 'month' | 'week'

  ads_enabled: boolean
  coins_multiplier: number
  can_participate_battles: boolean
  battle_priority: SubscriptionBattlePriority
  analytics_level: SubscriptionAnalyticsLevel

  content_access: SubscriptionContentAccess
  content_limit_ratio?: number

  featured_status: boolean
  perks: Record<string, unknown>

  // Structured, product-facing feature flags (preferred by clients over `perks`).
  // Backed by `subscription_plans.features` in Supabase; kept here as a safe fallback.
  features?: Record<string, unknown>
}

const FREE_PERKS: Record<string, unknown> = {
  ads: {
    interstitial_every_songs: 3,
    interstitial_every_videos: 2,
  },
  playback: {
    skips: { unlimited: false, per_hour: 5 },
    background_play: false,
  },
  playlists: {
    create: false,
  },
  downloads: { enabled: false },
  quality: {
    audio: 'low',
    video: 'low',
  },
  battles: {
    access: 'limited',
    priority: 'none',
  },
  gifting: {
    tier: 'limited',
  },
  content: {
    exclusive: false,
    early_access: false,
  },
  content_access: 'limited',
  content_limit_ratio: 0.3,
  recognition: {
    vip_badge: false,
  },
  exclusive_content: 'none',
  monthly_bonus_coins: 0,
}

const FREE_FEATURES: Record<string, unknown> = {
  ads_enabled: true,
  coins_multiplier: 1,
  analytics_level: 'basic',
  live_battles: false,
  live_battle_access: 'watch_only',
  priority_live_battle: 'none',
  premium_content: false,
  featured_status: false,
  background_play: false,
  video_downloads: false,
  audio_quality: 'standard',
  audio_max_kbps: 128,
  priority_live_access: false,
  highlighted_comments: false,
  exclusive_content: false,
  ads: {
    enabled: true,
    interstitial_every_songs: 2,
  },
  live: {
    access: 'watch_only',
    can_participate: false,
    can_create_battle: false,
    priority: 'none',
    priority_access: false,
    song_requests: {
      enabled: false,
    },
    highlighted_comments: false,
  },
  content: {
    exclusive: false,
    early_access: false,
    limit_ratio: 0.3,
  },
  gifting: {
    tier: 'limited',
    can_send: true,
    priority_visibility: false,
  },
  quality: {
    audio: 'standard',
    audio_max_kbps: 128,
  },
  tickets: {
    buy: {
      enabled: true,
      tiers: ['standard'],
    },
    priority_booking: false,
    redeem_bonus_coins: false,
  },
  playback: {
    skips_per_hour: 6,
    background_play: false,
  },
  downloads: {
    enabled: false,
    video_enabled: false,
  },
  analytics: {
    level: 'basic',
  },
  battles: {
    enabled: false,
    priority: 'none',
  },
  comments: {
    highlighted: false,
  },
  recognition: {
    vip_badge: false,
  },
  featured: false,
  vip: {
    badge: false,
  },
  vip_badge: false,
  monetization: {
    ads_revenue: false,
  },
  content_access: 'limited',
  content_limit_ratio: 0.3,
  coins: {
    monthly_free: {
      amount: 0,
    },
    monthly_bonus: {
      amount: 0,
    },
  },
  monthly_bonus_coins: 0,
  max_songs: 3,
  max_videos: 2,
  can_host_live: false,
  ai_monthly_limit: 1,
  ai_max_length_minutes: 1,
  advanced_analytics: false,
  priority_support: false,
  homepage_feature: false,
}

const PREMIUM_PERKS: Record<string, unknown> = {
  playback: {
    skips: { unlimited: true },
    background_play: true,
  },
  downloads: { enabled: true, offline_listening: true },
  playlists: {
    create: true,
  },
  live_streams: {
    watch_artists_djs: true,
    watch_battles: true,
  },
  quality: {
    audio: 'high',
    audio_max_kbps: 320,
    video: 'high',
  },
  gifting: {
    tier: 'standard',
  },
  live: {
    access: 'standard',
    song_requests: { enabled: false },
    highlighted_comments: false,
    priority_access: false,
  },
  content: {
    exclusive: false,
    early_access: true,
  },
  content_access: 'standard',
  tickets: {
    buy: {
      enabled: true,
      tiers: ['standard', 'vip'],
    },
    priority_booking: false,
    redeem_bonus_coins: false,
  },
  battles: {
    access: 'full',
    priority: 'standard',
  },
  billing: {
    cancel_anytime: true,
  },
  recognition: {
    vip_badge: false,
  },
  exclusive_content: 'early_releases',
  monthly_bonus_coins: 0,
}

const PREMIUM_FEATURES: Record<string, unknown> = {
  ads_enabled: false,
  coins_multiplier: 2,
  analytics_level: 'standard',
  live_battles: true,
  live_battle_access: 'standard',
  priority_live_battle: 'standard',
  premium_content: true,
  featured_status: false,
  background_play: true,
  video_downloads: false,
  audio_quality: 'high',
  audio_max_kbps: 320,
  priority_live_access: false,
  highlighted_comments: false,
  exclusive_content: false,
  ads: {
    enabled: false,
    interstitial_every_songs: 0,
  },
  live: {
    access: 'standard',
    can_participate: true,
    can_create_battle: false,
    priority: 'standard',
    priority_access: false,
    song_requests: {
      enabled: false,
    },
    highlighted_comments: false,
  },
  content: {
    exclusive: false,
    early_access: true,
    limit_ratio: 1,
  },
  gifting: {
    tier: 'standard',
    can_send: true,
    priority_visibility: false,
  },
  quality: {
    audio: 'high',
    audio_max_kbps: 320,
  },
  tickets: {
    buy: {
      enabled: true,
      tiers: ['standard', 'vip'],
    },
    priority_booking: false,
    redeem_bonus_coins: false,
  },
  playback: {
    skips_per_hour: -1,
    background_play: true,
  },
  downloads: {
    enabled: true,
    video_enabled: false,
  },
  analytics: {
    level: 'standard',
  },
  battles: {
    enabled: true,
    priority: 'standard',
  },
  comments: {
    highlighted: false,
  },
  recognition: {
    vip_badge: false,
  },
  featured: false,
  vip: {
    badge: false,
  },
  vip_badge: false,
  monetization: {
    ads_revenue: false,
  },
  content_access: 'standard',
  content_limit_ratio: 1,
  coins: {
    monthly_free: {
      amount: 0,
    },
    monthly_bonus: {
      amount: 0,
    },
  },
  monthly_bonus_coins: 0,
  max_songs: -1,
  max_videos: -1,
  can_host_live: true,
  ai_monthly_limit: 30,
  ai_max_length_minutes: 3,
  advanced_analytics: true,
  priority_support: true,
  homepage_feature: true,
}

const PLATINUM_PERKS: Record<string, unknown> = {
  playback: {
    skips: { unlimited: true },
    background_play: true,
  },
  downloads: { enabled: true, offline_listening: true, video_enabled: true },
  playlists: {
    create: true,
    mix: true,
  },
  live_streams: {
    watch_artists_djs: true,
    watch_battles: true,
  },
  quality: {
    audio: 'studio',
    audio_max_kbps: 320,
    audio_max_bit_depth: 24,
    audio_max_sample_rate_khz: 44.1,
    video: 'high',
  },
  gifting: {
    tier: 'vip',
  },
  live: {
    access: 'priority',
    song_requests: { enabled: true },
    highlighted_comments: true,
    priority_access: true,
  },
  content: {
    exclusive: true,
    early_access: true,
  },
  content_access: 'exclusive',
  tickets: {
    buy: {
      enabled: true,
      tiers: ['standard', 'vip', 'priority'],
    },
    priority_booking: true,
    redeem_bonus_coins: true,
  },
  battles: {
    access: 'full',
    priority: 'priority',
    replay_anytime: true,
  },
  billing: {
    cancel_anytime: true,
  },
  coins: {
    monthly_free: {
      enabled: true,
      amount: 200,
    },
    monthly_bonus: {
      amount: 200,
    },
  },
  badge: {
    name: 'VIP',
  },
  artist_support: {
    enabled: true,
  },
  recognition: {
    vip_badge: true,
  },
  exclusive_content: 'full',
  featured: true,
  featured_status: true,
  monthly_bonus_coins: 200,
}

const PLATINUM_FEATURES: Record<string, unknown> = {
  ads_enabled: false,
  coins_multiplier: 3,
  analytics_level: 'advanced',
  live_battles: true,
  live_battle_access: 'priority',
  priority_live_battle: 'priority',
  premium_content: true,
  featured_status: true,
  background_play: true,
  video_downloads: true,
  audio_quality: 'high',
  audio_max_kbps: 320,
  priority_live_access: true,
  highlighted_comments: true,
  exclusive_content: true,
  ads: {
    enabled: false,
    interstitial_every_songs: 0,
  },
  live: {
    access: 'priority',
    can_participate: true,
    can_create_battle: false,
    priority: 'priority',
    priority_access: true,
    song_requests: {
      enabled: true,
    },
    highlighted_comments: true,
  },
  content: {
    exclusive: true,
    early_access: true,
    limit_ratio: 1,
  },
  gifting: {
    tier: 'vip',
    can_send: true,
    priority_visibility: true,
  },
  quality: {
    audio: 'studio',
    audio_max_kbps: 320,
    audio_max_bit_depth: 24,
    audio_max_sample_rate_khz: 44.1,
  },
  tickets: {
    buy: {
      enabled: true,
      tiers: ['standard', 'vip', 'priority'],
    },
    priority_booking: true,
    redeem_bonus_coins: true,
  },
  playback: {
    skips_per_hour: -1,
    background_play: true,
  },
  downloads: {
    enabled: true,
    video_enabled: true,
  },
  analytics: {
    level: 'advanced',
  },
  battles: {
    enabled: true,
    priority: 'priority',
  },
  comments: {
    highlighted: true,
  },
  recognition: {
    vip_badge: true,
  },
  featured: true,
  vip: {
    badge: true,
  },
  vip_badge: true,
  monetization: {
    ads_revenue: false,
  },
  content_access: 'exclusive',
  content_limit_ratio: 1,
  coins: {
    monthly_free: {
      amount: 200,
    },
    monthly_bonus: {
      amount: 200,
    },
  },
  monthly_bonus_coins: 200,
  max_songs: -1,
  max_videos: -1,
  can_host_live: true,
  ai_monthly_limit: -1,
  ai_max_length_minutes: 5,
  advanced_analytics: true,
  priority_support: true,
  homepage_feature: true,
  elite_badge: true,
  priority_ai_queue: true,
}

const PREMIUM_WEEKLY_PERKS: Record<string, unknown> = {
  ...PREMIUM_PERKS,
}

const PREMIUM_WEEKLY_FEATURES: Record<string, unknown> = {
  ...PREMIUM_FEATURES,
}

const PLATINUM_WEEKLY_PERKS: Record<string, unknown> = {
  ...PLATINUM_PERKS,
  coins: {
    monthly_free: {
      enabled: true,
      amount: 50,
    },
    weekly_free: {
      enabled: true,
      amount: 50,
    },
    monthly_bonus: {
      amount: 50,
    },
  },
  monthly_bonus_coins: 50,
}

const PLATINUM_WEEKLY_FEATURES: Record<string, unknown> = {
  ...PLATINUM_FEATURES,
  coins: {
    monthly_free: {
      amount: 50,
    },
    weekly_free: {
      amount: 50,
    },
    monthly_bonus: {
      amount: 50,
    },
  },
  monthly_bonus_coins: 50,
}

export const SUBSCRIPTION_PLANS: Record<SubscriptionPlanId, SubscriptionEntitlements> = {
  free: {
    plan_id: 'free',
    name: 'Free',
    price_mwk: 0,
    billing_interval: 'month',
    ads_enabled: true,
    coins_multiplier: 1,
    can_participate_battles: true,
    battle_priority: 'none',
    analytics_level: 'basic',
    content_access: 'limited',
    content_limit_ratio: 0.3,
    featured_status: false,
    perks: FREE_PERKS,
    features: FREE_FEATURES,
  },
  premium: {
    plan_id: 'premium',
    name: 'Premium',
    price_mwk: 4000,
    billing_interval: 'month',
    ads_enabled: false,
    coins_multiplier: 2,
    can_participate_battles: true,
    battle_priority: 'standard',
    analytics_level: 'standard',
    content_access: 'standard',
    content_limit_ratio: 1,
    featured_status: false,
    perks: PREMIUM_PERKS,
    features: PREMIUM_FEATURES,
  },
  premium_weekly: {
    plan_id: 'premium_weekly',
    name: 'Premium (Weekly)',
    price_mwk: 1000,
    billing_interval: 'week',
    ads_enabled: false,
    coins_multiplier: 2,
    can_participate_battles: true,
    battle_priority: 'standard',
    analytics_level: 'standard',
    content_access: 'standard',
    content_limit_ratio: 1,
    featured_status: false,
    perks: PREMIUM_WEEKLY_PERKS,
    features: PREMIUM_WEEKLY_FEATURES,
  },
  platinum: {
    plan_id: 'platinum',
    name: 'Platinum',
    price_mwk: 8500,
    billing_interval: 'month',
    ads_enabled: false,
    coins_multiplier: 3,
    can_participate_battles: true,
    battle_priority: 'priority',
    analytics_level: 'advanced',
    content_access: 'exclusive',
    content_limit_ratio: 1,
    featured_status: true,
    perks: PLATINUM_PERKS,
    features: PLATINUM_FEATURES,
  },
  platinum_weekly: {
    plan_id: 'platinum_weekly',
    name: 'Platinum (Weekly)',
    price_mwk: 2125,
    billing_interval: 'week',
    ads_enabled: false,
    coins_multiplier: 3,
    can_participate_battles: true,
    battle_priority: 'priority',
    analytics_level: 'advanced',
    content_access: 'exclusive',
    content_limit_ratio: 1,
    featured_status: true,
    perks: PLATINUM_WEEKLY_PERKS,
    features: PLATINUM_WEEKLY_FEATURES,
  },
}

// --- Creator plans (Artists + DJs) ---
// These are distinct from listener tiers so the plan catalog can be filtered by audience.

SUBSCRIPTION_PLANS.artist_starter = {
  ...SUBSCRIPTION_PLANS.free,
  plan_id: 'artist_starter',
  name: 'Artist Free',
  price_mwk: 0,
  ads_enabled: true,
  coins_multiplier: 1,
  can_participate_battles: false,
  battle_priority: 'none',
  analytics_level: 'basic',
  content_access: 'limited',
  content_limit_ratio: 0.3,
  featured_status: false,
  perks: {
    ...SUBSCRIPTION_PLANS.free.perks,
    creator: {
      type: 'artist',
      uploads: { songs: 5, videos: 0, bulk_upload: false },
      monetization: {
        streams: false,
        coins: false,
        live: false,
        battles: false,
        fan_support: false,
      },
      withdrawals: { access: 'none' },
      live: { host: false, battles: false, multi_guest: false },
    },
    battles: { enabled: false, priority: 'none' },
    content: { exclusive: false, early_access: false },
    tickets: { sell: { enabled: false, tiers: [] } },
    recognition: { vip_badge: false },
  },
  features: {
    ...(SUBSCRIPTION_PLANS.free.features ?? {}),
    creator: {
      audience: 'artist',
      tier: 'free',
      uploads: { songs: 5, videos: 0, bulk_upload: false },
      analytics: {
        level: 'basic',
        views: true,
        likes: true,
        comments: false,
        revenue: false,
        watch_time: false,
        countries: false,
      },
      monetization: {
        streams: false,
        coins: false,
        live: false,
        battles: false,
        fan_support: false,
      },
      live: { host: false, battles: false, multi_guest: false },
      withdrawals: { access: 'none' },
    },
    battles: { enabled: false, priority: 'none' },
    content: { exclusive: false, early_access: false },
    tickets: { sell: { enabled: false, tiers: [] } },
    creator_type: 'artist',
    max_songs: 5,
    max_videos: 0,
    can_upload_videos: false,
    can_host_live: false,
    advanced_analytics: false,
    monetization_from_streams: false,
    monthly_bonus_coins: 0,
    vip_badge: false,
  },
}

SUBSCRIPTION_PLANS.artist_pro = {
  ...SUBSCRIPTION_PLANS.premium,
  plan_id: 'artist_pro',
  name: 'Artist Premium',
  price_mwk: 6000,
  ads_enabled: false,
  coins_multiplier: 2,
  can_participate_battles: true,
  battle_priority: 'standard',
  analytics_level: 'standard',
  content_access: 'standard',
  content_limit_ratio: 1,
  featured_status: false,
  perks: {
    ...SUBSCRIPTION_PLANS.premium.perks,
    creator: {
      type: 'artist',
      uploads: { songs: 20, videos: 5, bulk_upload: false },
      monetization: {
        streams: true,
        coins: true,
        live: true,
        battles: true,
        fan_support: false,
      },
      withdrawals: { access: 'limited' },
      live: { host: true, battles: true, multi_guest: false },
    },
    battles: { enabled: true, priority: 'standard' },
    content: { exclusive: false, early_access: true },
    tickets: { sell: { enabled: true, tiers: ['standard'] } },
    recognition: { vip_badge: false },
  },
  features: {
    ...(SUBSCRIPTION_PLANS.premium.features ?? {}),
    creator: {
      audience: 'artist',
      tier: 'premium',
      uploads: { songs: 20, videos: 5, bulk_upload: false },
      analytics: {
        level: 'medium',
        views: true,
        likes: true,
        comments: true,
        revenue: true,
        watch_time: false,
        countries: false,
      },
      monetization: {
        streams: true,
        coins: true,
        live: true,
        battles: true,
        fan_support: false,
      },
      live: { host: true, battles: true, multi_guest: false },
      withdrawals: { access: 'limited' },
    },
    battles: { enabled: true, priority: 'standard' },
    content: { exclusive: false, early_access: true },
    tickets: { sell: { enabled: true, tiers: ['standard'] } },
    creator_type: 'artist',
    max_songs: 20,
    max_videos: 5,
    can_upload_videos: true,
    can_host_live: true,
    advanced_analytics: true,
    monetization_from_streams: true,
    monthly_bonus_coins: 0,
    vip_badge: false,
  },
}

SUBSCRIPTION_PLANS.artist_premium = {
  ...SUBSCRIPTION_PLANS.platinum,
  plan_id: 'artist_premium',
  name: 'Artist Platinum',
  price_mwk: 12500,
  ads_enabled: false,
  coins_multiplier: 3,
  can_participate_battles: true,
  battle_priority: 'priority',
  analytics_level: 'advanced',
  content_access: 'exclusive',
  content_limit_ratio: 1,
  featured_status: true,
  perks: {
    ...SUBSCRIPTION_PLANS.platinum.perks,
    creator: {
      type: 'artist',
      uploads: { songs: 'unlimited', videos: 'unlimited', bulk_upload: true },
      monetization: {
        streams: true,
        coins: true,
        live: true,
        battles: true,
        fan_support: true,
      },
      withdrawals: { access: 'unlimited' },
      live: {
        host: true,
        battles: true,
        multi_guest: true,
        song_requests: true,
      },
    },
    battles: { enabled: true, priority: 'priority' },
    content: { exclusive: true, early_access: true },
    tickets: {
      sell: { enabled: true, tiers: ['standard', 'vip', 'priority'] },
    },
    recognition: { vip_badge: true },
    monthly_bonus_coins: 200,
  },
  features: {
    ...(SUBSCRIPTION_PLANS.platinum.features ?? {}),
    creator: {
      audience: 'artist',
      tier: 'platinum',
      uploads: { songs: -1, videos: -1, bulk_upload: true },
      analytics: {
        level: 'advanced',
        views: true,
        likes: true,
        comments: true,
        revenue: true,
        watch_time: true,
        countries: true,
      },
      monetization: {
        streams: true,
        coins: true,
        live: true,
        battles: true,
        fan_support: true,
      },
      live: {
        host: true,
        battles: true,
        multi_guest: true,
        song_requests: true,
      },
      withdrawals: { access: 'unlimited' },
    },
    battles: { enabled: true, priority: 'priority' },
    content: { exclusive: true, early_access: true },
    tickets: {
      sell: { enabled: true, tiers: ['standard', 'vip', 'priority'] },
    },
    creator_type: 'artist',
    max_songs: -1,
    max_videos: -1,
    can_upload_videos: true,
    can_host_live: true,
    advanced_analytics: true,
    monetization_from_streams: true,
    fan_support: true,
    monthly_bonus_coins: 200,
    vip_badge: true,
  },
}

SUBSCRIPTION_PLANS.dj_starter = {
  ...SUBSCRIPTION_PLANS.free,
  plan_id: 'dj_starter',
  name: 'DJ Free',
  price_mwk: 0,
  ads_enabled: true,
  coins_multiplier: 1,
  can_participate_battles: false,
  battle_priority: 'none',
  analytics_level: 'basic',
  content_access: 'limited',
  content_limit_ratio: 0.3,
  featured_status: false,
  perks: {
    ...SUBSCRIPTION_PLANS.free.perks,
    creator: {
      type: 'dj',
      uploads: { mixes: 5, bulk_upload: false },
      monetization: {
        live_gifts: false,
        battles: false,
        streams: false,
        fan_support: false,
      },
      withdrawals: { access: 'none' },
      live: { host: false, battles: false, dj_sets: false },
    },
    battles: { enabled: false, priority: 'none' },
    content: { exclusive: false, early_access: false },
    tickets: { sell: { enabled: false, tiers: [] } },
    recognition: { vip_badge: false },
  },
  features: {
    ...(SUBSCRIPTION_PLANS.free.features ?? {}),
    creator: {
      audience: 'dj',
      tier: 'free',
      uploads: { mixes: 5, bulk_upload: false },
      analytics: {
        level: 'basic',
        views: true,
        likes: false,
        comments: false,
        revenue: false,
      },
      monetization: {
        live_gifts: false,
        battles: false,
        streams: false,
        fan_support: false,
      },
      live: { host: false, battles: false, dj_sets: false },
      withdrawals: { access: 'none' },
    },
    battles: { enabled: false, priority: 'none' },
    content: { exclusive: false, early_access: false },
    tickets: { sell: { enabled: false, tiers: [] } },
    creator_type: 'dj',
    max_mixes: 5,
    livestream_dj_sets: false,
    advanced_analytics: false,
    monthly_bonus_coins: 0,
    vip_badge: false,
  },
}

SUBSCRIPTION_PLANS.dj_pro = {
  ...SUBSCRIPTION_PLANS.premium,
  plan_id: 'dj_pro',
  name: 'DJ Premium',
  price_mwk: 8000,
  ads_enabled: false,
  coins_multiplier: 2,
  can_participate_battles: true,
  battle_priority: 'standard',
  analytics_level: 'standard',
  content_access: 'standard',
  content_limit_ratio: 1,
  featured_status: false,
  perks: {
    ...SUBSCRIPTION_PLANS.premium.perks,
    creator: {
      type: 'dj',
      uploads: { mixes: 'unlimited', bulk_upload: false },
      monetization: {
        live_gifts: true,
        battles: true,
        streams: true,
        fan_support: false,
      },
      withdrawals: { access: 'limited' },
      live: { host: true, battles: true, dj_sets: true },
    },
    battles: { enabled: true, priority: 'standard' },
    content: { exclusive: false, early_access: true },
    tickets: { sell: { enabled: true, tiers: ['standard'] } },
    recognition: { vip_badge: false },
  },
  features: {
    ...(SUBSCRIPTION_PLANS.premium.features ?? {}),
    creator: {
      audience: 'dj',
      tier: 'premium',
      uploads: { mixes: -1, bulk_upload: false },
      analytics: {
        level: 'medium',
        views: true,
        likes: true,
        comments: true,
        revenue: true,
      },
      monetization: {
        live_gifts: true,
        battles: true,
        streams: true,
        fan_support: false,
      },
      live: { host: true, battles: true, dj_sets: true },
      withdrawals: { access: 'limited' },
    },
    battles: { enabled: true, priority: 'standard' },
    content: { exclusive: false, early_access: true },
    tickets: { sell: { enabled: true, tiers: ['standard'] } },
    creator_type: 'dj',
    max_mixes: -1,
    livestream_dj_sets: true,
    can_host_live: true,
    advanced_analytics: true,
    monthly_bonus_coins: 0,
    vip_badge: false,
  },
}

SUBSCRIPTION_PLANS.dj_premium = {
  ...SUBSCRIPTION_PLANS.platinum,
  plan_id: 'dj_premium',
  name: 'DJ Platinum',
  price_mwk: 15000,
  ads_enabled: false,
  coins_multiplier: 3,
  can_participate_battles: true,
  battle_priority: 'priority',
  analytics_level: 'advanced',
  content_access: 'exclusive',
  content_limit_ratio: 1,
  featured_status: true,
  perks: {
    ...SUBSCRIPTION_PLANS.platinum.perks,
    creator: {
      type: 'dj',
      uploads: { mixes: 'unlimited', bulk_upload: true },
      monetization: {
        live_gifts: true,
        battles: true,
        streams: true,
        fan_support: true,
      },
      withdrawals: { access: 'unlimited' },
      live: {
        host: true,
        battles: true,
        dj_sets: true,
        audience_voting: true,
        rewards: true,
        song_requests: true,
        highlighted_comments: true,
        polls: true,
      },
    },
    battles: { enabled: true, priority: 'priority' },
    content: { exclusive: true, early_access: true },
    tickets: {
      sell: { enabled: true, tiers: ['standard', 'vip', 'priority'] },
    },
    recognition: { vip_badge: true },
    monthly_bonus_coins: 200,
  },
  features: {
    ...(SUBSCRIPTION_PLANS.platinum.features ?? {}),
    creator: {
      audience: 'dj',
      tier: 'platinum',
      uploads: { mixes: -1, bulk_upload: true },
      analytics: {
        level: 'advanced',
        views: true,
        likes: true,
        comments: true,
        revenue: true,
        watch_time: true,
        countries: true,
      },
      monetization: {
        live_gifts: true,
        battles: true,
        streams: true,
        fan_support: true,
      },
      live: {
        host: true,
        battles: true,
        dj_sets: true,
        audience_voting: true,
        rewards: true,
        song_requests: true,
        highlighted_comments: true,
        polls: true,
      },
      withdrawals: { access: 'unlimited' },
    },
    battles: { enabled: true, priority: 'priority' },
    content: { exclusive: true, early_access: true },
    tickets: {
      sell: { enabled: true, tiers: ['standard', 'vip', 'priority'] },
    },
    creator_type: 'dj',
    max_mixes: -1,
    livestream_dj_sets: true,
    can_host_live: true,
    advanced_analytics: true,
    fan_support: true,
    monthly_bonus_coins: 200,
    vip_badge: true,
  },
}

SUBSCRIPTION_PLANS.starter = {
  ...SUBSCRIPTION_PLANS.free,
  plan_id: 'starter',
  name: 'Starter',
}

SUBSCRIPTION_PLANS.pro = {
  ...SUBSCRIPTION_PLANS.premium,
  plan_id: 'pro',
  name: 'Pro (Legacy)',
}

SUBSCRIPTION_PLANS.elite = {
  ...SUBSCRIPTION_PLANS.platinum,
  plan_id: 'elite',
  name: 'Elite (Legacy)',
}

SUBSCRIPTION_PLANS.pro_weekly = {
  ...SUBSCRIPTION_PLANS.premium_weekly,
  plan_id: 'pro_weekly',
  name: 'Pro (Weekly, Legacy)',
}

SUBSCRIPTION_PLANS.elite_weekly = {
  ...SUBSCRIPTION_PLANS.platinum_weekly,
  plan_id: 'elite_weekly',
  name: 'Elite (Weekly, Legacy)',
}

const LEGACY_CONSUMER_PLAN_ALIASES: Record<string, SubscriptionPlanId> = {
  starter: 'free',
  pro: 'premium',
  elite: 'platinum',
  pro_weekly: 'premium_weekly',
  elite_weekly: 'platinum_weekly',
  vip: 'platinum',
}

const CANONICAL_CONSUMER_PLAN_ALIASES: Record<string, SubscriptionPlanId> = {
  free: 'starter',
  premium: 'pro',
  platinum: 'elite',
  premium_weekly: 'pro_weekly',
  platinum_weekly: 'elite_weekly',
}

export function asSubscriptionPlanId(value: unknown): SubscriptionPlanId | null {

  // Keep this usable from both server and client code.
  if (typeof value !== 'string' && typeof value !== 'number') return null
  const v = String(value).trim().toLowerCase()
  // Conservative: safe for URLs/IDs and avoids surprising whitespace.
  // Examples: free, premium, consumer_plus, artist-trial
  if (!v) return null
  if (v.length > 64) return null
  if (!/^[a-z0-9][a-z0-9_-]{1,63}$/.test(v)) return null
  return v
}

export function normalizeSubscriptionPlanId(value: unknown): SubscriptionPlanId | null {
  const planId = asSubscriptionPlanId(value)
  if (!planId) return null

  return LEGACY_CONSUMER_PLAN_ALIASES[planId] ?? planId
}

export function getEquivalentSubscriptionPlanIds(value: unknown): SubscriptionPlanId[] {
  const planId = asSubscriptionPlanId(value)
  if (!planId) return []

  const normalized = normalizeSubscriptionPlanId(planId) ?? planId
  const ids = new Set<SubscriptionPlanId>([planId, normalized])
  const legacyAlias = CANONICAL_CONSUMER_PLAN_ALIASES[normalized]
  if (legacyAlias) ids.add(legacyAlias)

  return [...ids]
}

export function getSubscriptionEntitlements(planId: SubscriptionPlanId): SubscriptionEntitlements {
  const normalized = normalizeSubscriptionPlanId(planId)
  if (normalized && SUBSCRIPTION_PLANS[normalized]) return SUBSCRIPTION_PLANS[normalized]
  return SUBSCRIPTION_PLANS.free
}

// Prefer an exact ID match when available (important for consumer APIs where
// clients rely on `plan_id` and display names like Free/Premium/Platinum).
// Falls back to the normalized lookup, then ultimately to Free (safe default).
export function getSubscriptionEntitlementsExact(planId: SubscriptionPlanId): SubscriptionEntitlements {
  const exact = asSubscriptionPlanId(planId)
  if (exact && SUBSCRIPTION_PLANS[exact]) return SUBSCRIPTION_PLANS[exact]

  const normalized = exact ? normalizeSubscriptionPlanId(exact) : normalizeSubscriptionPlanId(planId)
  if (normalized && SUBSCRIPTION_PLANS[normalized]) return SUBSCRIPTION_PLANS[normalized]
  return SUBSCRIPTION_PLANS.free
}

export function formatSubscriptionPlanLabel(planId: SubscriptionPlanId): string {
  const normalized = normalizeSubscriptionPlanId(planId)
  return (normalized && SUBSCRIPTION_PLANS[normalized] ? SUBSCRIPTION_PLANS[normalized] : SUBSCRIPTION_PLANS.free).name
}
