import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { SUBSCRIPTION_PLANS, getSubscriptionEntitlementsExact, normalizeSubscriptionPlanId } from '@/lib/subscription/plans'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}


function isMissingColumn(err: unknown, column: string): boolean {
	const e = err as { message?: unknown; code?: unknown } | null
	const message = String(e?.message ?? '')
	const code = String(e?.code ?? '')
	return code === '42703' || message.toLowerCase().includes(column.toLowerCase())
}

function toNumber(value: unknown, fallback = 0): number {
	if (typeof value === 'number' && Number.isFinite(value)) return value
	if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value)
	return fallback
}

function toIntervalCount(value: unknown): number {
	const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN
	if (!Number.isFinite(n)) return 1
	return Math.max(1, Math.min(24, Math.trunc(n)))
}

function normalizeBillingInterval(value: unknown): 'month' | 'week' {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'week' || s === 'weekly') return 'week'
	return 'month'
}

function isMissingTable(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { message?: unknown; code?: unknown; details?: unknown; hint?: unknown }
	const code = typeof e.code === 'string' ? e.code : ''
	if (code === '42P01' || code === 'PGRST205') return true
	const msg = [e.message, e.details, e.hint]
		.map((x) => (typeof x === 'string' ? x : ''))
		.join(' ')
		.toLowerCase()
	return msg.includes('does not exist') || msg.includes('could not find the table') || msg.includes('schema cache')
}

function isExplicitCreatorPlanId(planId: string): boolean {
	return /^(artist_|creator_|dj_)/i.test(planId)
}

const FALLBACK_CONSUMER_PLAN_IDS = ['free', 'premium', 'premium_weekly', 'platinum', 'platinum_weekly'] as const
const FALLBACK_ARTIST_PLAN_IDS = ['artist_starter', 'artist_pro', 'artist_premium'] as const
const FALLBACK_DJ_PLAN_IDS = ['dj_starter', 'dj_pro', 'dj_premium'] as const
const FALLBACK_CREATOR_LEGACY_PLAN_IDS = ['starter', 'pro', 'pro_weekly', 'elite', 'elite_weekly'] as const

function fallbackPlans(audience?: string | null) {
	const a = String(audience ?? 'consumer').trim().toLowerCase()
	const ids =
		a === 'artist'
			? FALLBACK_ARTIST_PLAN_IDS
			: a === 'dj'
				? FALLBACK_DJ_PLAN_IDS
				: a === 'creator'
					? FALLBACK_CREATOR_LEGACY_PLAN_IDS
					: FALLBACK_CONSUMER_PLAN_IDS

	return ids
		.map((id) => SUBSCRIPTION_PLANS[id])
		.filter(Boolean)
		.slice()
		.sort((x, y) => x.price_mwk - y.price_mwk)
		.map((p) => ({
			plan_id: p.plan_id,
			name: p.name,
			price_mwk: p.price_mwk,
			billing_interval: p.billing_interval,
			currency: 'MWK',
			price_per_interval_mwk: p.price_mwk,
			interval_count: 1,
			total_price_mwk: p.price_mwk,
		}))
}

/**
 * Public endpoint intended for the consumer app.
 *
 * Returns the current subscription plan catalog (pricing + IDs).
 *
 * Notes:
 * - DB tables are RLS deny-all; this route uses the service-role key on the server.
 * - If your `subscription_plans` table does not have `audience`/`is_active`, this route will gracefully fall back.
 */
export async function GET(req: NextRequest) {
	const audience = (req.nextUrl.searchParams.get('audience') ?? 'consumer').trim().toLowerCase()
	const supabase = tryCreateSupabaseAdminClient()
	const intervalCount = toIntervalCount(req.nextUrl.searchParams.get('interval_count') ?? req.nextUrl.searchParams.get('months') ?? 1)
	if (!supabase) {
		return NextResponse.json(
			{
				ok: true,
				source: 'fallback',
				interval_count: intervalCount,
				plans: fallbackPlans(audience).map((p) => ({
					...p,
					interval_count: intervalCount,
					total_price_mwk: p.price_per_interval_mwk * intervalCount,
				})),
			},
			{ headers: { 'cache-control': 'no-store' } },
		)
	}

	const wantAudienceFilter = audience === 'consumer' || audience === 'artist' || audience === 'dj'

	const baseSelectWithAudience = 'audience,plan_id,name,price_mwk,billing_interval,is_active'
	const baseSelectNoAudience = 'plan_id,name,price_mwk,billing_interval,is_active'
	const baseSelectMinimal = 'plan_id,name,price_mwk,billing_interval'

	let data: unknown[] | null = null
	let error: unknown = null

	// 1) Try with audience + is_active.
	let query = supabase.from('subscription_plans').select(baseSelectWithAudience)
	if (wantAudienceFilter) query = query.eq('audience', audience)
	query = query.eq('is_active', true).order('price_mwk', { ascending: true })
	{
		const res = await query
		data = (res.data as unknown[] | null) ?? null
		error = res.error
	}

	// 2) If audience column missing, retry without it.
	if (error && isMissingColumn(error, 'audience')) {
		let q2 = supabase.from('subscription_plans').select(baseSelectNoAudience)
		q2 = q2.eq('is_active', true).order('price_mwk', { ascending: true })
		const res = await q2
		data = (res.data as unknown[] | null) ?? null
		error = res.error
	}

	// 3) If is_active missing, retry minimal and return everything (assume active).
	if (error && isMissingColumn(error, 'is_active')) {
		let q3 = supabase.from('subscription_plans').select(wantAudienceFilter ? baseSelectWithAudience : baseSelectMinimal)
		if (wantAudienceFilter) {
			q3 = q3.eq('audience', audience)
		}
		q3 = q3.order('price_mwk', { ascending: true })
		{
			const res = await q3
			data = (res.data as unknown[] | null) ?? null
			error = res.error
		}
		if (error && isMissingColumn(error, 'audience')) {
			const res = await supabase.from('subscription_plans').select(baseSelectMinimal).order('price_mwk', { ascending: true })
			data = (res.data as unknown[] | null) ?? null
			error = res.error
		}
	}

	if (error) {
		if (isMissingTable(error)) {
			return NextResponse.json(
				{
					ok: true,
					source: 'fallback',
					interval_count: intervalCount,
					plans: fallbackPlans(audience).map((p) => ({
						...p,
						interval_count: intervalCount,
						total_price_mwk: p.price_per_interval_mwk * intervalCount,
					})),
				},
				{ headers: { 'cache-control': 'no-store' } },
			)
		}
		const e = error as { message?: unknown } | null
		return json({ error: String(e?.message ?? 'Query failed') }, { status: 500 })
	}

	// Normalize output: only expose safe fields.
	const normalizedPlans = (data ?? [])
		.map((row) => {
			const r = (row ?? {}) as Record<string, unknown>
			const planId = typeof r.plan_id === 'string' ? r.plan_id : null
			const name = typeof r.name === 'string' ? r.name : null
			if (!planId || !name) return null
			if (audience === 'consumer' && isExplicitCreatorPlanId(planId)) return null
			const billingInterval = normalizeBillingInterval(r.billing_interval)
			const pricePerInterval = toNumber(r.price_mwk, 0)
			const normalizedPlanId = audience === 'consumer' ? normalizeSubscriptionPlanId(planId) ?? planId : planId
			const fallback = getSubscriptionEntitlementsExact(normalizedPlanId)
			const mappedFromLegacy = normalizedPlanId !== planId
			return {
				plan_id: normalizedPlanId,
				name: mappedFromLegacy && audience === 'consumer' ? fallback.name : name,
				// Backward-compatible: keep `price_mwk` as the per-interval price.
				price_mwk: pricePerInterval,
				billing_interval: billingInterval,
				currency: 'MWK',
				price_per_interval_mwk: pricePerInterval,
				interval_count: intervalCount,
				total_price_mwk: pricePerInterval * intervalCount,
				__priority: mappedFromLegacy ? 1 : 0,
			}
		})
		.filter(
			(p): p is {
				plan_id: string
				name: string
				price_mwk: number
				billing_interval: 'month' | 'week'
				currency: 'MWK'
				price_per_interval_mwk: number
				interval_count: number
				total_price_mwk: number
				__priority: number
			} => Boolean(p),
		)

	const deduped = new Map<string, (typeof normalizedPlans)[number]>()
	for (const plan of normalizedPlans) {
		const existing = deduped.get(plan.plan_id)
		if (!existing || plan.__priority < existing.__priority) deduped.set(plan.plan_id, plan)
	}

	const plans = [...deduped.values()]
		.map(({ __priority, ...plan }) => plan)
		.sort((a, b) => a.price_mwk - b.price_mwk)

	if (plans.length === 0) {
		// If the catalog hasn't been seeded yet, still return the default plan set.
		return NextResponse.json(
			{
				ok: true,
				source: 'fallback',
				interval_count: intervalCount,
				plans: fallbackPlans(audience).map((p) => ({
					...p,
					interval_count: intervalCount,
					total_price_mwk: p.price_per_interval_mwk * intervalCount,
				})),
			},
			{ headers: { 'cache-control': 'no-store' } },
		)
	}

	return NextResponse.json(
		{ ok: true, source: 'db', interval_count: intervalCount, plans },
		{
			headers: {
				'cache-control': 'no-store',
			},
		},
	)
}
