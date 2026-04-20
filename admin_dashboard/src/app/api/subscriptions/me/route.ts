import { NextResponse } from 'next/server'
import type { DecodedIdToken } from 'firebase-admin/auth'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getSubscriptionUserIdCandidatesForFirebaseUid } from '@/lib/subscription/resolve-user-id'
import {
	asSubscriptionPlanId,
	getEquivalentSubscriptionPlanIds,
	getSubscriptionEntitlementsExact,
	normalizeSubscriptionPlanId,
	type SubscriptionAnalyticsLevel,
	type SubscriptionBattlePriority,
	type SubscriptionContentAccess,
	type SubscriptionEntitlements,
} from '@/lib/subscription/plans'
import { mergeRecordsDeep } from '@/lib/subscription/merge-records-deep'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function isMissingTableErrorMessage(message: unknown): boolean {
	const s = String(message ?? '')
	return /schema cache|could not find|does not exist|PGRST205/i.test(s)
}

function getBearerToken(req: Request): string | null {
	const raw = req.headers.get('authorization') || req.headers.get('Authorization')
	if (!raw) return null
	const m = raw.match(/^Bearer\s+(.+)$/i)
	return m ? m[1]!.trim() : null
}

function toNumber(value: unknown, fallback = 0): number {
	if (typeof value === 'number' && Number.isFinite(value)) return value
	if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value)
	return fallback
}

function asBattlePriority(value: unknown, fallback: SubscriptionBattlePriority): SubscriptionBattlePriority {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'none' || s === 'standard' || s === 'priority') return s
	return fallback
}

function asAnalyticsLevel(value: unknown, fallback: SubscriptionAnalyticsLevel): SubscriptionAnalyticsLevel {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'basic' || s === 'standard' || s === 'advanced') return s
	return fallback
}

function asContentAccess(value: unknown, fallback: SubscriptionContentAccess): SubscriptionContentAccess {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'limited' || s === 'standard' || s === 'exclusive') return s
	return fallback
}

function asBillingInterval(value: unknown, fallback: SubscriptionEntitlements['billing_interval']): SubscriptionEntitlements['billing_interval'] {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'month' || s === 'weekly' || s === 'week') return s === 'month' ? 'month' : 'week'
	return fallback
}

type ActiveSubscriptionRow = {
	id: number
	plan_id: string
	status: string
	started_at: string | null
	ends_at: string | null
	auto_renew: boolean | null
	country_code: string | null
	source: string | null
	meta: unknown
}

type PlanRow = {
	plan_id: string
	name: string
	price_mwk: number
	billing_interval: string
	coins_multiplier?: number | null
	ads_enabled?: boolean | null
	can_participate_battles?: boolean | null
	battle_priority?: string | null
	analytics_level?: string | null
	content_access?: string | null
	content_limit_ratio?: number | null
	featured_status?: boolean | null
	perks?: unknown
	features?: unknown
}

/**
 * Public endpoint intended for the consumer app.
 *
 * Auth:
 * - Send `Authorization: Bearer <firebase_id_token>`
 *
 * Response:
 * - active subscription (if any)
 * - plan + computed entitlements
 */
export async function GET(req: Request) {
	const idToken = getBearerToken(req)
	if (!idToken) return json({ error: 'Missing Authorization: Bearer <firebase_id_token>' }, { status: 401 })

	let decoded: DecodedIdToken
	try {
		const auth = getFirebaseAdminAuth()
		decoded = await auth.verifyIdToken(idToken)
	} catch {
		return json({ error: 'Invalid auth token' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		const fallback = getSubscriptionEntitlementsExact('free')
		return NextResponse.json(
			{
				ok: true,
				warning: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY). Returning Free plan defaults.',
				user: { uid: decoded.uid },
				subscription: null,
				plan: {
					plan_id: fallback.plan_id,
					name: fallback.name,
					price_mwk: fallback.price_mwk,
					billing_interval: fallback.billing_interval,
					features: fallback.features ?? {},
				},
				entitlements: fallback,
			},
			{ headers: { 'cache-control': 'no-store' } },
		)
	}

	// We store user subscriptions keyed by user_id. For Firebase-based consumer auth,
	// we use the Firebase `uid` as the user_id.
	const userId = decoded.uid

	let active: ActiveSubscriptionRow | null = null
	let missingUserSubscriptions = false
	{
		const { data, error } = await supabase
			.from('user_subscriptions')
			.select('id,plan_id,status,started_at,ends_at,auto_renew,country_code,source,meta')
			.eq('user_id', userId)
			.eq('status', 'active')
			.order('created_at', { ascending: false })
			.limit(1)
			.maybeSingle<ActiveSubscriptionRow>()

		if (error) {
			if (isMissingTableErrorMessage(error.message)) missingUserSubscriptions = true
			else return json({ error: error.message }, { status: 500 })
		} else {
			active = data ?? null
		}
	}

	// Legacy fallback: older systems may have stored user_id as an internal UUID. When that
	// happens, look up candidate ids for this Firebase UID and query across them.
	if (!active && !missingUserSubscriptions) {
		const candidates = await getSubscriptionUserIdCandidatesForFirebaseUid({ supabase, firebaseUid: userId }).catch(() => [])
		const ids = Array.from(new Set((candidates ?? []).map((v) => String(v ?? '').trim()).filter(Boolean)))
		if (ids.length && !(ids.length === 1 && ids[0] === userId)) {
			const { data, error } = await supabase
				.from('user_subscriptions')
				.select('id,plan_id,status,started_at,ends_at,auto_renew,country_code,source,meta')
				.in('user_id', ids)
				.eq('status', 'active')
				.order('created_at', { ascending: false })
				.limit(1)
				.maybeSingle<ActiveSubscriptionRow>()

			if (error) {
				if (isMissingTableErrorMessage(error.message)) missingUserSubscriptions = true
				else return json({ error: error.message }, { status: 500 })
			} else {
				active = data ?? null
			}
		}
	}

	const activePlanId = String(active?.plan_id ?? 'free').trim() || 'free'
	const planId = normalizeSubscriptionPlanId(activePlanId) ?? asSubscriptionPlanId(activePlanId) ?? 'free'
	const planLookupIds = Array.from(new Set([activePlanId, ...getEquivalentSubscriptionPlanIds(activePlanId)]))

	// Prefer DB plan row (source of truth), but fall back to local defaults.
	let planRow: PlanRow | null = null
	let missingSubscriptionPlans = false
	{
		const { data: rows, error: planError } = await supabase
			.from('subscription_plans')
			.select(
				'plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,perks,features',
			)
			.in('plan_id', planLookupIds)
			.limit(Math.max(1, planLookupIds.length))

		if (planError) {
			if (isMissingTableErrorMessage(planError.message)) missingSubscriptionPlans = true
			else return json({ error: planError.message }, { status: 500 })
		} else {
			const planRows = ((rows ?? []) as PlanRow[])
			planRow =
				planRows.find((row) => String(row.plan_id ?? '').trim() === planId) ??
				planRows.find((row) => String(row.plan_id ?? '').trim() === activePlanId) ??
				planRows[0] ??
				null
		}
	}

	const fallback = getSubscriptionEntitlementsExact(planId)
	const rowPlanId = planRow ? normalizeSubscriptionPlanId(planRow.plan_id) ?? String(planRow.plan_id ?? planId) : planId
	const mappedFromLegacy = planRow ? rowPlanId !== String(planRow.plan_id ?? '').trim() : false
	const fallbackPerks = (fallback.perks ?? {}) as Record<string, unknown>
	const fallbackFeatures = (fallback.features ?? {}) as Record<string, unknown>
	const dbPerks =
		planRow?.perks && typeof planRow.perks === 'object'
			? (planRow.perks as Record<string, unknown>)
			: null
	const dbFeatures =
		planRow?.features && typeof planRow.features === 'object'
			? (planRow.features as Record<string, unknown>)
			: null
	const mergedPerks = mergeRecordsDeep(fallbackPerks, dbPerks) ?? fallbackPerks
	const mergedFeatures = mergeRecordsDeep(fallbackFeatures, dbFeatures) ?? fallbackFeatures

	const entitlements: SubscriptionEntitlements = planRow
		? {
			plan_id: rowPlanId,
			name: mappedFromLegacy ? fallback.name : planRow.name,
			price_mwk: toNumber(planRow.price_mwk, fallback.price_mwk),
			billing_interval: asBillingInterval(planRow.billing_interval, fallback.billing_interval),
			ads_enabled: Boolean(planRow.ads_enabled ?? fallback.ads_enabled),
			coins_multiplier: toNumber(planRow.coins_multiplier, fallback.coins_multiplier),
			can_participate_battles: Boolean(planRow.can_participate_battles ?? fallback.can_participate_battles),
			battle_priority: asBattlePriority(planRow.battle_priority, fallback.battle_priority),
			analytics_level: asAnalyticsLevel(planRow.analytics_level, fallback.analytics_level),
			content_access: asContentAccess(planRow.content_access, fallback.content_access),
			content_limit_ratio:
				planRow.content_limit_ratio == null
					? fallback.content_limit_ratio
					: toNumber(planRow.content_limit_ratio, fallback.content_limit_ratio ?? 0),
			featured_status: Boolean(planRow.featured_status ?? fallback.featured_status),
			perks: mergedPerks,
			features: mergedFeatures,
		}
		: fallback

	const warning = missingUserSubscriptions
		? 'Subscriptions not configured (missing user_subscriptions table).'
		: missingSubscriptionPlans
			? 'Subscriptions not configured (missing subscription_plans table).'
			: undefined

	return NextResponse.json(
		{
			ok: true,
			...(warning ? { warning } : null),
			user: { uid: decoded.uid },
			subscription: active
				?
					{
						id: active.id,
						plan_id: planId,
						status: active.status,
						started_at: active.started_at,
						ends_at: active.ends_at,
						auto_renew: active.auto_renew,
						country_code: active.country_code,
						source: active.source,
					}
				: null,
			plan: planRow
				?
					{
						plan_id: rowPlanId,
						name: mappedFromLegacy ? fallback.name : planRow.name,
						price_mwk: toNumber(planRow.price_mwk, 0),
						billing_interval: String(planRow.billing_interval ?? 'month'),
						features: mergedFeatures,
					}
				: {
						plan_id: entitlements.plan_id,
						name: entitlements.name,
						price_mwk: entitlements.price_mwk,
						billing_interval: entitlements.billing_interval,
						features: entitlements.features ?? fallback.features,
					},
			entitlements,
		},
		{
			headers: {
				'cache-control': 'no-store',
			},
		},
	)
}
