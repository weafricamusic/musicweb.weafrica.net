export const PROMOTION_TYPES = ['artist', 'dj', 'battle', 'event', 'ride'] as const
export type PromotionType = (typeof PROMOTION_TYPES)[number]

export const PROMOTION_SURFACES = ['home_banner', 'discover', 'feed', 'live_battle', 'events'] as const
export type PromotionSurface = (typeof PROMOTION_SURFACES)[number]

export const PROMOTION_STATUSES = ['draft', 'scheduled', 'active', 'paused', 'ended', 'rejected'] as const
export type PromotionStatus = (typeof PROMOTION_STATUSES)[number]

export const PAID_PROMOTION_STATUSES = ['pending', 'approved', 'rejected', 'active', 'completed', 'cancelled'] as const
export type PaidPromotionStatus = (typeof PAID_PROMOTION_STATUSES)[number]

export const AD_CAMPAIGN_TYPES = ['admob', 'direct_brand', 'in_app_promo'] as const
export type AdCampaignType = (typeof AD_CAMPAIGN_TYPES)[number]

export const AD_CAMPAIGN_FORMATS = ['banner', 'video', 'interstitial', 'native', 'audio', 'promo_card'] as const
export type AdCampaignFormat = (typeof AD_CAMPAIGN_FORMATS)[number]

export const AD_CAMPAIGN_SURFACES = ['home_banner', 'discover', 'feed', 'live_battle', 'events', 'ride', 'audio_interstitial'] as const
export type AdCampaignSurface = (typeof AD_CAMPAIGN_SURFACES)[number]

export const AD_CAMPAIGN_STATUSES = ['draft', 'scheduled', 'active', 'paused', 'completed', 'cancelled'] as const
export type AdCampaignStatus = (typeof AD_CAMPAIGN_STATUSES)[number]

export const AD_CAMPAIGN_APPROVAL_STATUSES = ['pending', 'approved', 'rejected'] as const
export type AdCampaignApprovalStatus = (typeof AD_CAMPAIGN_APPROVAL_STATUSES)[number]

export const PROMOTION_PLANS = ['basic', 'pro', 'premium'] as const
export type PromotionPlan = (typeof PROMOTION_PLANS)[number]

export const PROMOTION_SOCIAL_PLATFORMS = ['facebook', 'instagram', 'x', 'whatsapp'] as const
export type PromotionSocialPlatform = (typeof PROMOTION_SOCIAL_PLATFORMS)[number]

export const DEFAULT_PROMOTION_SOCIAL_LINKS = {
	facebook: 'https://www.facebook.com/share/1DzRfNVBSc/',
	instagram: 'https://www.instagram.com/weafricamusic?igsh=b3l0eHc3cm5zNmQx',
	x: 'https://x.com/WeafricaMusic',
	whatsapp: 'https://whatsapp.com/channel/0029VbCKK5V0gcfObTkWfT12',
} as const satisfies Record<PromotionSocialPlatform, string>

export const PROMOTION_PLAN_CONFIG = {
	basic: {
		label: 'Basic',
		coins: 50,
		feedWeight: 1,
		featuredBadge: false,
		bannerPlacement: false,
		socialPlatforms: [] as PromotionSocialPlatform[],
	},
	pro: {
		label: 'Pro',
		coins: 200,
		feedWeight: 2,
		featuredBadge: true,
		bannerPlacement: false,
		socialPlatforms: ['facebook', 'instagram'] as PromotionSocialPlatform[],
	},
	premium: {
		label: 'Premium',
		coins: 500,
		feedWeight: 3,
		featuredBadge: true,
		bannerPlacement: true,
		socialPlatforms: ['facebook', 'instagram', 'x', 'whatsapp'] as PromotionSocialPlatform[],
	},
} as const satisfies Record<PromotionPlan, {
	label: string
	coins: number
	feedWeight: number
	featuredBadge: boolean
	bannerPlacement: boolean
	socialPlatforms: PromotionSocialPlatform[]
}>

export const PROMOTION_STATUS_FLOW = ['pending', 'approved', 'active', 'completed'] as const

export function isPromotionType(raw: unknown): raw is PromotionType {
	return PROMOTION_TYPES.includes(String(raw ?? '') as PromotionType)
}

export function isPromotionSurface(raw: unknown): raw is PromotionSurface {
	return PROMOTION_SURFACES.includes(String(raw ?? '') as PromotionSurface)
}

export function isPromotionStatus(raw: unknown): raw is PromotionStatus {
	return PROMOTION_STATUSES.includes(String(raw ?? '') as PromotionStatus)
}

export function isPaidPromotionStatus(raw: unknown): raw is PaidPromotionStatus {
	return PAID_PROMOTION_STATUSES.includes(String(raw ?? '') as PaidPromotionStatus)
}

export function isAdCampaignType(raw: unknown): raw is AdCampaignType {
	return AD_CAMPAIGN_TYPES.includes(String(raw ?? '') as AdCampaignType)
}

export function isAdCampaignFormat(raw: unknown): raw is AdCampaignFormat {
	return AD_CAMPAIGN_FORMATS.includes(String(raw ?? '') as AdCampaignFormat)
}

export function isAdCampaignSurface(raw: unknown): raw is AdCampaignSurface {
	return AD_CAMPAIGN_SURFACES.includes(String(raw ?? '') as AdCampaignSurface)
}

export function isAdCampaignStatus(raw: unknown): raw is AdCampaignStatus {
	return AD_CAMPAIGN_STATUSES.includes(String(raw ?? '') as AdCampaignStatus)
}

export function isAdCampaignApprovalStatus(raw: unknown): raw is AdCampaignApprovalStatus {
	return AD_CAMPAIGN_APPROVAL_STATUSES.includes(String(raw ?? '') as AdCampaignApprovalStatus)
}

export function isPromotionPlan(raw: unknown): raw is PromotionPlan {
	return PROMOTION_PLANS.includes(String(raw ?? '') as PromotionPlan)
}

export function isPromotionSocialPlatform(raw: unknown): raw is PromotionSocialPlatform {
	return PROMOTION_SOCIAL_PLATFORMS.includes(String(raw ?? '') as PromotionSocialPlatform)
}

export function normalizeCountryCode(raw: unknown, fallback = 'MW'): string {
	const code = String(raw ?? '').trim().toUpperCase()
	if (/^[A-Z]{2}$/.test(code)) return code
	return fallback
}

export function toIsoOrNull(raw: unknown): string | null {
	const value = String(raw ?? '').trim()
	if (!value) return null
	const parsed = new Date(value)
	if (Number.isNaN(parsed.getTime())) return null
	return parsed.toISOString()
}

export function toPositiveInt(raw: unknown): number | null {
	const value = Number(raw)
	if (!Number.isFinite(value)) return null
	const int = Math.trunc(value)
	return int > 0 ? int : null
}

export function addDaysIso(startIso: string, days: number): string {
	const base = new Date(startIso)
	const endMs = base.getTime() + Math.max(1, Math.trunc(days)) * 24 * 60 * 60 * 1000
	return new Date(endMs).toISOString()
}

export function normalizePromotionPlan(raw: unknown, fallback: PromotionPlan = 'basic'): PromotionPlan {
	const plan = String(raw ?? '').trim().toLowerCase()
	if (isPromotionPlan(plan)) return plan
	return fallback
}

export function labelPromotionPlan(raw: unknown): string {
	const plan = normalizePromotionPlan(raw)
	return PROMOTION_PLAN_CONFIG[plan].label
}

export function promotionPlanCoins(raw: unknown): number {
	return PROMOTION_PLAN_CONFIG[normalizePromotionPlan(raw)].coins
}

export function promotionPlanFeedWeight(raw: unknown): number {
	return PROMOTION_PLAN_CONFIG[normalizePromotionPlan(raw)].feedWeight
}

export function promotionPlanPlatforms(raw: unknown): PromotionSocialPlatform[] {
	return PROMOTION_PLAN_CONFIG[normalizePromotionPlan(raw)].socialPlatforms
}

export function normalizePromotionStatus(raw: unknown, fallback: PromotionStatus = 'draft'): PromotionStatus {
	const status = String(raw ?? '').trim().toLowerCase()
	if (isPromotionStatus(status)) return status
	return fallback
}

export function normalizePaidPromotionStatus(raw: unknown, fallback: PaidPromotionStatus = 'pending'): PaidPromotionStatus {
	const status = String(raw ?? '').trim().toLowerCase()
	if (isPaidPromotionStatus(status)) return status
	return fallback
}

export function daysRemaining(endIso: string | null | undefined, now = new Date()): number {
	if (!endIso) return 0
	const end = new Date(endIso)
	if (Number.isNaN(end.getTime())) return 0
	const ms = end.getTime() - now.getTime()
	if (ms <= 0) return 0
	return Math.ceil(ms / (24 * 60 * 60 * 1000))
}

export function promotionFeedBonus(input: {
	plan?: unknown
	endIso?: string | null
	boostMultiplier?: unknown
	now?: Date
}): number {
	const plan = normalizePromotionPlan(input.plan)
	const days = daysRemaining(input.endIso, input.now)
	const multiplierRaw = Number(input.boostMultiplier ?? 1)
	const multiplier = Number.isFinite(multiplierRaw) && multiplierRaw > 0 ? multiplierRaw : 1
	return Math.round(500 * days * promotionPlanFeedWeight(plan) * multiplier)
}

export function promotionStatusTone(raw: unknown): 'neutral' | 'warning' | 'success' | 'danger' | 'info' {
	const status = String(raw ?? '').trim().toLowerCase()
	if (status === 'active' || status === 'approved' || status === 'completed') return 'success'
	if (status === 'pending' || status === 'paused') return 'warning'
	if (status === 'scheduled') return 'info'
	if (status === 'rejected' || status === 'cancelled' || status === 'ended') return 'danger'
	return 'neutral'
}

export function readPromotionSocialLink(platform: PromotionSocialPlatform, override?: unknown): string {
	const value = String(override ?? '').trim()
	return value || DEFAULT_PROMOTION_SOCIAL_LINKS[platform]
}

export function buildPromotionShareMessage(input: {
	title: string
	artistName?: string | null
	plan?: unknown
	contentUrl?: string | null
}): string {
	const title = input.title.trim() || 'Featured on WeAfrica Music'
	const artist = String(input.artistName ?? '').trim()
	const plan = labelPromotionPlan(input.plan)
	const url = String(input.contentUrl ?? '').trim()
	const prefix = artist ? `${artist} - ${title}` : title
	const suffix = url ? `\n${url}` : ''
	return `${prefix}\nPromoted on WeAfrica Music (${plan}).${suffix}`.trim()
}

export function buildPromotionShareUrl(input: {
	platform: PromotionSocialPlatform
	title: string
	artistName?: string | null
	plan?: unknown
	contentUrl?: string | null
	overrideLink?: string | null
}): string {
	const platform = input.platform
	const baseLink = readPromotionSocialLink(platform, input.overrideLink)
	const message = buildPromotionShareMessage(input)
	const contentUrl = String(input.contentUrl ?? '').trim() || baseLink

	if (platform === 'facebook') {
		const u = new URL('https://www.facebook.com/sharer/sharer.php')
		u.searchParams.set('u', contentUrl)
		u.searchParams.set('quote', message)
		return u.toString()
	}

	if (platform === 'x') {
		const u = new URL('https://twitter.com/intent/tweet')
		u.searchParams.set('text', message)
		if (contentUrl) u.searchParams.set('url', contentUrl)
		return u.toString()
	}

	if (platform === 'whatsapp') {
		const u = new URL('https://wa.me/')
		u.searchParams.set('text', `${message}${contentUrl ? `\n${contentUrl}` : ''}`.trim())
		return u.toString()
	}

	return baseLink
}

export function labelPromotionType(raw: unknown): string {
	const t = String(raw ?? '').trim().toLowerCase()
	if (t === 'dj') return 'DJ'
	if (t === 'battle') return 'Battle'
	if (t === 'event') return 'Event'
	if (t === 'ride') return 'Ride'
	return 'Artist'
}

export function labelPromotionSurface(raw: unknown): string {
	const s = String(raw ?? '').trim().toLowerCase()
	if (s === 'home_banner') return 'Home Banner'
	if (s === 'discover') return 'Discover'
	if (s === 'feed') return 'Feed'
	if (s === 'live_battle') return 'Live Battle'
	if (s === 'events') return 'Events'
	return 'Unknown'
}

export function labelAdCampaignType(raw: unknown): string {
	const value = String(raw ?? '').trim().toLowerCase()
	if (value === 'admob') return 'AdMob'
	if (value === 'direct_brand') return 'Direct Brand'
	if (value === 'in_app_promo') return 'In-app Promo'
	return 'Unknown'
}

export function labelAdCampaignFormat(raw: unknown): string {
	const value = String(raw ?? '').trim().toLowerCase()
	if (value === 'promo_card') return 'Promo Card'
	if (value === 'audio') return 'Audio'
	if (value === 'interstitial') return 'Interstitial'
	if (value === 'native') return 'Native'
	if (value === 'video') return 'Video'
	if (value === 'banner') return 'Banner'
	return 'Unknown'
}

export function labelAdCampaignSurface(raw: unknown): string {
	const value = String(raw ?? '').trim().toLowerCase()
	if (value === 'home_banner') return 'Home Banner'
	if (value === 'discover') return 'Discover'
	if (value === 'feed') return 'Feed'
	if (value === 'live_battle') return 'Live Battle'
	if (value === 'events') return 'Events'
	if (value === 'ride') return 'Ride'
	if (value === 'audio_interstitial') return 'Audio Interstitial'
	return 'Unknown'
}

export function labelAdCampaignApprovalStatus(raw: unknown): string {
	const value = String(raw ?? '').trim().toLowerCase()
	if (value === 'approved') return 'Approved'
	if (value === 'rejected') return 'Rejected'
	return 'Pending'
}

export function labelAdCampaignStatus(raw: unknown): string {
	const value = String(raw ?? '').trim().toLowerCase()
	if (value === 'scheduled') return 'Scheduled'
	if (value === 'active') return 'Active'
	if (value === 'paused') return 'Paused'
	if (value === 'completed') return 'Completed'
	if (value === 'cancelled') return 'Cancelled'
	return 'Draft'
}

export function engagementLevel(views: number, clicks: number): 'High' | 'Medium' | 'Low' {
	if (views <= 0 && clicks <= 0) return 'Low'
	const safeViews = Math.max(views, 1)
	const ctr = clicks / safeViews
	if (ctr >= 0.03 || clicks >= 300) return 'High'
	if (ctr >= 0.015 || clicks >= 100) return 'Medium'
	return 'Low'
}

export function promotionTypeFromContentType(raw: unknown): PromotionType {
	const t = String(raw ?? '').trim().toLowerCase()
	if (t === 'dj' || t === 'dj_profile' || t === 'djprofile') return 'dj'
	if (t === 'battle' || t === 'live_battle' || t === 'livestream' || t === 'live') return 'battle'
	if (t === 'event') return 'event'
	if (t === 'ride' || t === 'weafrica_ride' || t === 'transport') return 'ride'
	return 'artist'
}
