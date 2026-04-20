const ARTIST_PLAN_PREFIX = /^artist_/i
const DJ_PLAN_PREFIX = /^dj_/i
const CREATOR_PLAN_PREFIX = /^creator_/i

export type SubscriptionAudience = 'consumer' | 'artist' | 'dj' | 'creator' | 'other'

export function normalizeSubscriptionAudience(value: unknown): SubscriptionAudience {
	const audience = String(value ?? '').trim().toLowerCase()
	if (audience === 'consumer') return 'consumer'
	if (audience === 'artist') return 'artist'
	if (audience === 'dj') return 'dj'
	if (audience === 'creator' || audience === 'both') return 'creator'
	return 'other'
}

export function isCreatorPlanId(planId: unknown): boolean {
	const normalized = String(planId ?? '').trim().toLowerCase()
	if (!normalized) return false
	return ARTIST_PLAN_PREFIX.test(normalized) || DJ_PLAN_PREFIX.test(normalized) || CREATOR_PLAN_PREFIX.test(normalized)
}

export function isArtistPlan(plan: { plan_id?: unknown; audience?: unknown } | null | undefined): boolean {
	if (!plan) return false
	const audience = normalizeSubscriptionAudience(plan.audience)
	if (audience === 'artist') return true
	if (audience === 'consumer' || audience === 'dj') return false
	const planId = String(plan.plan_id ?? '').trim().toLowerCase()
	if (!planId) return false
	// Some deployments label creator plans as `creator` / `both`. Prefer explicit prefixes when present.
	if (audience === 'creator') return !DJ_PLAN_PREFIX.test(planId)
	return ARTIST_PLAN_PREFIX.test(planId)
}

export function isDjPlan(plan: { plan_id?: unknown; audience?: unknown } | null | undefined): boolean {
	if (!plan) return false
	const audience = normalizeSubscriptionAudience(plan.audience)
	if (audience === 'dj') return true
	if (audience === 'consumer' || audience === 'artist') return false
	const planId = String(plan.plan_id ?? '').trim().toLowerCase()
	if (!planId) return false
	// Some deployments label creator plans as `creator` / `both`. Prefer explicit prefixes when present.
	if (audience === 'creator') return !ARTIST_PLAN_PREFIX.test(planId)
	return DJ_PLAN_PREFIX.test(planId)
}

export function isConsumerPlan(plan: { plan_id?: unknown; audience?: unknown } | null | undefined): boolean {
	if (!plan) return false
	const audience = normalizeSubscriptionAudience(plan.audience)
	if (audience === 'consumer') return true
	if (audience === 'artist' || audience === 'dj' || audience === 'creator') return false
	return !isCreatorPlanId(plan.plan_id)
}