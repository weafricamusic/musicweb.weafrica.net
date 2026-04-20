import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

export type AdminSubscriptionRole = 'artist' | 'dj'

export type AdminDefaultPlan = {
	plan_id: string
	name: string | null
}

type DbPlanRow = {
	plan_id?: unknown
	name?: unknown
	audience?: unknown
	price_mwk?: unknown
	is_active?: unknown
	active?: unknown
}

function isMissingColumn(err: unknown, column: string): boolean {
	const e = err as { message?: unknown; code?: unknown } | null
	const message = String(e?.message ?? '')
	const code = String(e?.code ?? '')
	return code === '42703' || message.toLowerCase().includes(column.toLowerCase())
}

function normalizeString(value: unknown): string {
	return typeof value === 'string' ? value.trim() : String(value ?? '').trim()
}

function toLower(value: unknown): string {
	return normalizeString(value).toLowerCase()
}

function toNumber(value: unknown, fallback = 0): number {
	if (typeof value === 'number' && Number.isFinite(value)) return value
	if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value)
	return fallback
}

function isActivePlan(row: DbPlanRow): boolean {
	const isActive = row.is_active
	if (typeof isActive === 'boolean') return isActive
	const active = row.active
	if (typeof active === 'boolean') return active
	return true
}

function scorePlan(row: DbPlanRow, role: AdminSubscriptionRole): { score: number; price: number; plan_id: string; name: string | null } {
	const planId = toLower(row.plan_id)
	const audience = toLower(row.audience)
	const price = toNumber(row.price_mwk, 0)
	const name = typeof row.name === 'string' && row.name.trim() ? row.name.trim() : null

	let score = 0

	if (!planId) score -= 10

	// Audience signals (some DBs use creator/both).
	if (role === 'artist') {
		if (audience === 'artist') score += 100
		else if (audience === 'creator' || audience === 'both') score += 80
		else if (!audience) score += 20
		else if (audience === 'consumer') score += 10
		else if (audience === 'dj') score -= 40
	} else {
		if (audience === 'dj') score += 100
		else if (audience === 'creator' || audience === 'both') score += 80
		else if (!audience) score += 20
		else if (audience === 'consumer') score += 10
		else if (audience === 'artist') score -= 40
	}

	// Plan id signals.
	if (planId.startsWith(`${role}_`)) score += 50
	if (role === 'artist' && planId.includes('artist')) score += 30
	if (role === 'dj' && planId.includes('dj')) score += 30

	const CREATOR_TIER_IDS = new Set(['starter', 'pro', 'elite', 'pro_weekly', 'elite_weekly'])
	const CONSUMER_TIER_IDS = new Set(['free', 'premium', 'platinum', 'premium_weekly', 'platinum_weekly'])

	if (CREATOR_TIER_IDS.has(planId)) score += 25
	if (CONSUMER_TIER_IDS.has(planId)) score += 15

	// Prefer non-free for the quick 30-day action.
	if (price > 0) score += 10
	if (planId === 'free' || planId === 'starter') score -= 100

	return { score, price, plan_id: planId, name }
}

async function loadPlanRows(supabase: SupabaseClient): Promise<DbPlanRow[]> {
	const attempts = [
		'audience,plan_id,name,price_mwk,is_active,active',
		'audience,plan_id,name,price_mwk,is_active',
		'audience,plan_id,name,price_mwk,active',
		'audience,plan_id,name,price_mwk',
		'plan_id,name,price_mwk,is_active,active',
		'plan_id,name,price_mwk,is_active',
		'plan_id,name,price_mwk,active',
		'plan_id,name,price_mwk',
	] as const

	for (const select of attempts) {
		const { data, error } = await supabase
			.from('subscription_plans')
			.select(select)
			.order('price_mwk', { ascending: true })
			.limit(200)

		if (!error) return (data ?? []) as unknown as DbPlanRow[]

		// Only keep retrying if we suspect a missing column; otherwise, give the next attempt a chance anyway.
		const missing =
			isMissingColumn(error, 'audience') ||
			isMissingColumn(error, 'is_active') ||
			isMissingColumn(error, 'active') ||
			isMissingColumn(error, 'price_mwk')
		if (!missing) continue
	}

	return []
}

export async function getAdminDefaultPlanForRole(args: {
	supabase: SupabaseClient
	role: AdminSubscriptionRole
}): Promise<AdminDefaultPlan | null> {
	const rows = await loadPlanRows(args.supabase)
	const candidates = rows.filter((r) => normalizeString(r.plan_id))
	if (candidates.length === 0) return null

	const scored = candidates
		.filter((r) => isActivePlan(r))
		.map((r) => {
			const scored = scorePlan(r, args.role)
			return {
				row: r,
				score: scored.score,
				price: scored.price,
				plan_id: normalizeString(r.plan_id).toLowerCase(),
				name: scored.name,
			}
		})

	// If everything is inactive (or we couldn't detect it), fall back to all.
	const list = scored.length
		? scored
		: candidates.map((r) => {
			const s = scorePlan(r, args.role)
			return { row: r, score: s.score, price: s.price, plan_id: normalizeString(r.plan_id).toLowerCase(), name: s.name }
		})

	list.sort((a, b) => b.score - a.score || a.price - b.price || a.plan_id.localeCompare(b.plan_id))

	// Never auto-pick free-like plans for quick subscribe.
	const best = list.find((p) => p?.plan_id && p.plan_id !== 'free' && p.plan_id !== 'starter')
	if (!best?.plan_id) return null
	return { plan_id: best.plan_id, name: best.name }
}
