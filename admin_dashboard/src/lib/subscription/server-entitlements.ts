import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

import {
	asSubscriptionPlanId,
	getEquivalentSubscriptionPlanIds,
	getSubscriptionEntitlementsExact,
	normalizeSubscriptionPlanId,
	type SubscriptionEntitlements,
} from '@/lib/subscription/plans'
import { mergeRecordsDeep } from '@/lib/subscription/merge-records-deep'
import { getSubscriptionUserIdCandidatesForFirebaseUid } from '@/lib/subscription/resolve-user-id'

function isMissingTableErrorMessage(message: unknown): boolean {
	const s = String(message ?? '')
	return /schema cache|could not find|does not exist|PGRST205/i.test(s)
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
	created_at?: string | null
}

type PlanRow = {
	plan_id: string
	name: string
	price_mwk: number
	billing_interval: string
	perks?: unknown
	features?: unknown
	ads_enabled?: boolean | null
	coins_multiplier?: number | null
	can_participate_battles?: boolean | null
	battle_priority?: string | null
	analytics_level?: string | null
	content_access?: string | null
	content_limit_ratio?: number | null
	featured_status?: boolean | null
}

function toNumber(value: unknown, fallback = 0): number {
	if (typeof value === 'number' && Number.isFinite(value)) return value
	if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value)
	return fallback
}

function asBillingInterval(value: unknown, fallback: SubscriptionEntitlements['billing_interval']): SubscriptionEntitlements['billing_interval'] {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'month' || s === 'weekly' || s === 'week') return s === 'month' ? 'month' : 'week'
	return fallback
}

export async function getServerEntitlementsForUserId(args: {
	supabase: SupabaseClient
	userId: string
}): Promise<{
	active: ActiveSubscriptionRow | null
	entitlements: SubscriptionEntitlements
	warning?: string
}> {
	const userId = String(args.userId ?? '').trim()
	if (!userId) {
		return {
			active: null,
			entitlements: getSubscriptionEntitlementsExact('starter'),
			warning: 'Missing userId',
		}
	}

	let active: ActiveSubscriptionRow | null = null
	let missingUserSubscriptions = false
	{
		const { data, error } = await args.supabase
			.from('user_subscriptions')
			.select('id,plan_id,status,started_at,ends_at,auto_renew,country_code,source,meta,created_at')
			.eq('user_id', userId)
			.eq('status', 'active')
			.order('created_at', { ascending: false })
			.limit(1)
			.maybeSingle<ActiveSubscriptionRow>()

		if (error) {
			if (isMissingTableErrorMessage(error.message)) missingUserSubscriptions = true
			else throw new Error(error.message)
		} else {
			active = data ?? null
		}
	}

	// Legacy fallback: older systems may have stored subscription.user_id as an internal UUID.
	// When the caller passes a Firebase UID, query across all known ids for that uid.
	if (!active && !missingUserSubscriptions) {
		const candidates = await getSubscriptionUserIdCandidatesForFirebaseUid({ supabase: args.supabase, firebaseUid: userId }).catch(() => [])
		const ids = Array.from(new Set((candidates ?? []).map((v) => String(v ?? '').trim()).filter(Boolean)))
		if (ids.length && !(ids.length === 1 && ids[0] === userId)) {
			const { data, error } = await args.supabase
				.from('user_subscriptions')
				.select('id,plan_id,status,started_at,ends_at,auto_renew,country_code,source,meta,created_at')
				.in('user_id', ids)
				.eq('status', 'active')
				.order('created_at', { ascending: false })
				.limit(1)
				.maybeSingle<ActiveSubscriptionRow>()

			if (error) {
				if (isMissingTableErrorMessage(error.message)) missingUserSubscriptions = true
				else throw new Error(error.message)
			} else {
				active = data ?? null
			}
		}
	}

	const activePlanId = String(active?.plan_id ?? 'starter').trim() || 'starter'
	const requestedPlanId = asSubscriptionPlanId(activePlanId) ?? 'starter'
	const normalizedPlanId = normalizeSubscriptionPlanId(activePlanId)
	const planLookupIds = [...new Set([requestedPlanId, ...getEquivalentSubscriptionPlanIds(requestedPlanId)])]

	let planRow: PlanRow | null = null
	let missingSubscriptionPlans = false
	{
		const { data: rows, error: planError } = await args.supabase
			.from('subscription_plans')
			.select(
				'plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,perks,features',
			)
			.in('plan_id', planLookupIds)
			.limit(Math.max(1, planLookupIds.length))

		if (planError) {
			if (isMissingTableErrorMessage(planError.message)) missingSubscriptionPlans = true
			else throw new Error(planError.message)
		} else {
			const planRows = (rows ?? []) as PlanRow[]
			planRow =
				planRows.find((row) => String(row.plan_id ?? '').trim() === requestedPlanId) ??
				planRows.find((row) => String(row.plan_id ?? '').trim() === normalizedPlanId) ??
				planRows[0] ??
				null
		}
	}

	const fallback = getSubscriptionEntitlementsExact(requestedPlanId)
	const fallbackPerks = (fallback.perks ?? {}) as Record<string, unknown>
	const fallbackFeatures = (fallback.features ?? {}) as Record<string, unknown>

	const dbPerks = planRow?.perks && typeof planRow.perks === 'object' ? (planRow.perks as Record<string, unknown>) : null
	const dbFeatures = planRow?.features && typeof planRow.features === 'object' ? (planRow.features as Record<string, unknown>) : null
	const mergedPerks = mergeRecordsDeep(fallbackPerks, dbPerks) ?? fallbackPerks
	const mergedFeatures = mergeRecordsDeep(fallbackFeatures, dbFeatures) ?? fallbackFeatures

	const entitlements: SubscriptionEntitlements = planRow
		? {
			...fallback,
			plan_id: requestedPlanId,
			name:
				String(planRow.plan_id ?? '').trim() && String(planRow.plan_id ?? '').trim() !== requestedPlanId
					? fallback.name
					: String(planRow.name ?? fallback.name),
			price_mwk: toNumber(planRow.price_mwk, fallback.price_mwk),
			billing_interval: asBillingInterval(planRow.billing_interval, fallback.billing_interval),
			perks: mergedPerks,
			features: mergedFeatures,
		}
		: fallback

	const warning = missingUserSubscriptions
		? 'Subscriptions not configured (missing user_subscriptions table).'
		: missingSubscriptionPlans
			? 'Subscriptions not configured (missing subscription_plans table).'
			: undefined

	return { active, entitlements, ...(warning ? { warning } : null) }
}
