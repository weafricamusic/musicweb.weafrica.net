import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { asSubscriptionPlanId } from '@/lib/subscription/plans'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

type PlanRow = {
	plan_id: string
	audience?: string | null
	name: string
	price_mwk: number
	billing_interval: 'month' | 'week'
	coins_multiplier: number
	ads_enabled: boolean
	can_participate_battles: boolean
	battle_priority: 'none' | 'standard' | 'priority'
	analytics_level: 'basic' | 'standard' | 'advanced'
	content_access: 'limited' | 'standard' | 'exclusive'
	content_limit_ratio: number | null
	featured_status: boolean
	is_active: boolean
	sort_order?: number | null
	features: Record<string, unknown>
	perks?: Record<string, unknown> | null
	marketing?: Record<string, unknown> | null
	trial_eligible?: boolean | null
	trial_duration_days?: number | null
	created_at: string
	updated_at: string
}

function isMissingColumn(err: any, column: string): boolean {
	const message = String(err?.message ?? '')
	const code = String(err?.code ?? '')
	return (
		code === '42703' ||
		message.includes(`column subscription_plans.${column} does not exist`) ||
		message.toLowerCase().includes('does not exist')
	)
}

function withoutMissingLegacyColumns(payload: Record<string, unknown>, err: any): boolean {
	let mutated = false
	for (const col of ['role', 'plan', 'price'] as const) {
		if (col in payload && isMissingColumn(err, col)) {
			delete payload[col]
			mutated = true
		}
	}
	return mutated
}

const SELECT_WITH_AUDIENCE =
	'audience,plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,is_active,sort_order,features,perks,marketing,trial_eligible,trial_duration_days,created_at,updated_at'
const SELECT_NO_AUDIENCE =
	'plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,is_active,sort_order,features,perks,marketing,trial_eligible,trial_duration_days,created_at,updated_at'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

type ConsumerSeedPlanId = 'free' | 'premium' | 'platinum'

function isConsumerSeedPlanId(value: string): value is ConsumerSeedPlanId {
	return value === 'free' || value === 'premium' || value === 'platinum'
}

function defaultAudienceForPlanId(planId: string): 'consumer' | 'artist' | 'dj' {
	if (planId.startsWith('artist_')) return 'artist'
	if (planId.startsWith('dj_')) return 'dj'
	return 'consumer'
}

function defaultTrialEligibleForPlanId(planId: string): boolean {
	return planId === 'artist_starter' || planId === 'dj_starter'
}

function defaultTrialDurationDaysForPlanId(planId: string): number {
	return defaultTrialEligibleForPlanId(planId) ? 30 : 0
}

function defaultSortOrderForPlanId(planId: string): number | null {
	switch (planId) {
		case 'free':
			return 10
		case 'premium':
			return 20
		case 'platinum':
			return 30
		case 'artist_starter':
			return 110
		case 'artist_pro':
			return 120
		case 'artist_premium':
			return 130
		case 'dj_starter':
			return 210
		case 'dj_pro':
			return 220
		case 'dj_premium':
			return 230
		default:
			return null
	}
}

function buildConsumerSeedFeatures(planId: ConsumerSeedPlanId): Record<string, unknown> {
	if (planId === 'free') {
		return {
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
		}
	}

	if (planId === 'premium') {
		return {
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
		}
	}

	return {
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
			audio: 'high',
			audio_max_kbps: 320,
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
	}
}

export async function GET() {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	let data: any[] | null = null
	let error: any = null
	;({ data, error } = await supabase.from('subscription_plans').select(SELECT_WITH_AUDIENCE).order('price_mwk', { ascending: true }))
	if (error && isMissingColumn(error, 'audience')) {
		;({ data, error } = await supabase.from('subscription_plans').select(SELECT_NO_AUDIENCE).order('price_mwk', { ascending: true }))
	}

	if (error) return json({ error: error.message }, { status: 500 })
	return json({ ok: true, plans: (data ?? []) as unknown as PlanRow[] })
}

type CreatePlanBody = {
	action: 'create_plan'
	plan_id: string
	audience?: 'consumer' | 'artist' | 'dj' | null
	name?: string
	price_mwk?: number
	billing_interval?: 'month' | 'week'
	coins_multiplier?: number
	ads_enabled?: boolean
	can_participate_battles?: boolean
	battle_priority?: 'none' | 'standard' | 'priority'
	analytics_level?: 'basic' | 'standard' | 'advanced'
	content_access?: 'limited' | 'standard' | 'exclusive'
	content_limit_ratio?: number | null
	featured_status?: boolean
	is_active?: boolean
	sort_order?: number | null
	features?: Record<string, unknown>
	perks?: Record<string, unknown>
	marketing?: Record<string, unknown>
	trial_eligible?: boolean
	trial_duration_days?: number | null
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as CreatePlanBody | null
	if (!body || typeof body !== 'object' || body.action !== 'create_plan') return json({ error: 'Invalid body' }, { status: 400 })

	const planId = asSubscriptionPlanId(body.plan_id)
	if (!planId) return json({ error: 'Invalid plan_id' }, { status: 400 })
	const audience = body.audience == null ? defaultAudienceForPlanId(planId) : body.audience
	if (audience !== 'consumer' && audience !== 'artist' && audience !== 'dj') {
		return json({ error: 'Invalid audience' }, { status: 400 })
	}

	const isDefault = audience === 'consumer' && isConsumerSeedPlanId(planId)
	const priceMwk = body.price_mwk ?? (isDefault ? (planId === 'free' ? 0 : planId === 'premium' ? 4000 : 8500) : 0)
	const trialEligible = body.trial_eligible ?? defaultTrialEligibleForPlanId(planId)
	const trialDurationDays = trialEligible
		? Math.max(0, Number(body.trial_duration_days ?? defaultTrialDurationDaysForPlanId(planId)) || 0)
		: 0

	const payload: Record<string, unknown> = {
		audience,
		plan_id: planId,
		name: body.name ?? (isDefault ? (planId === 'free' ? 'Free' : planId === 'premium' ? 'Premium' : 'Platinum') : planId),
		price_mwk: priceMwk,
		billing_interval: body.billing_interval ?? 'month',
		coins_multiplier: body.coins_multiplier ?? (isDefault ? (planId === 'free' ? 1 : planId === 'premium' ? 2 : 3) : 1),
		ads_enabled: body.ads_enabled ?? (isDefault ? planId === 'free' : true),
		can_participate_battles: body.can_participate_battles ?? (isDefault ? planId !== 'free' : false),
		battle_priority: body.battle_priority ?? (isDefault ? (planId === 'platinum' ? 'priority' : planId === 'premium' ? 'standard' : 'none') : 'none'),
		analytics_level: body.analytics_level ?? (isDefault ? (planId === 'platinum' ? 'advanced' : planId === 'premium' ? 'standard' : 'basic') : 'basic'),
		content_access: body.content_access ?? (isDefault ? (planId === 'platinum' ? 'exclusive' : planId === 'premium' ? 'standard' : 'limited') : 'limited'),
		content_limit_ratio: body.content_limit_ratio ?? (isDefault ? (planId === 'free' ? 0.3 : 1) : null),
		featured_status: body.featured_status ?? (isDefault ? planId === 'platinum' : false),
		is_active: planId === 'free' && audience === 'consumer' ? true : (body.is_active ?? true),
		sort_order: body.sort_order ?? defaultSortOrderForPlanId(planId),
		features:
			body.features ??
			(isDefault ? buildConsumerSeedFeatures(planId) : {}),
		perks: body.perks ?? {},
		marketing: body.marketing ?? null,
		trial_eligible: trialEligible,
		trial_duration_days: trialDurationDays,
		updated_at: new Date().toISOString(),
	}

	// Legacy schema compatibility: some deployments still enforce NOT NULL columns
	// like `role` (and friends). We always send them when creating, then strip
	// if the DB doesn't have those columns.
	const upsertPayload: Record<string, unknown> = {
		...payload,
		role: audience,
		plan: planId,
		price: priceMwk,
	}

	let created: any = null
	let error: any = null
	let select = SELECT_WITH_AUDIENCE
	for (let attempt = 0; attempt < 3; attempt++) {
		;({ data: created, error } = await supabase
			.from('subscription_plans')
			.upsert(upsertPayload, { onConflict: 'plan_id' })
			.select(select)
			.single())
		if (!error) break

		let mutated = false
		if (select === SELECT_WITH_AUDIENCE && isMissingColumn(error, 'audience') && 'audience' in upsertPayload) {
			delete upsertPayload.audience
			select = SELECT_NO_AUDIENCE
			mutated = true
		}
		mutated = withoutMissingLegacyColumns(upsertPayload, error) || mutated
		if (!mutated) break
	}

	if (error) return json({ error: error.message }, { status: 500 })

	await logAdminAction({
		ctx,
		action: 'subscription_plans.create_or_seed',
		target_type: 'subscription_plan',
		target_id: planId,
		before_state: null,
		after_state: created as any,
		meta: { module: 'subscriptions' },
		req,
	})

	return json({ ok: true, plan: created as unknown as PlanRow })
}

type DeleteBody = {
	action: 'delete_plan'
	plan_id: string
}

export async function DELETE(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as DeleteBody | null
	if (!body || typeof body !== 'object' || body.action !== 'delete_plan') return json({ error: 'Invalid body' }, { status: 400 })

	const planId = asSubscriptionPlanId(body.plan_id)
	if (!planId) return json({ error: 'Invalid plan_id' }, { status: 400 })
	if (planId === 'free') return json({ error: 'Free plan cannot be deleted.' }, { status: 400 })

	// Only allow delete if there are no subscriptions referencing the plan.
	const { count } = await supabase
		.from('user_subscriptions')
		.select('id', { head: true, count: 'exact' })
		.eq('plan_id', planId)
		.limit(1)

	if ((count ?? 0) > 0) return json({ error: 'Plan has existing subscriptions. Disable it instead.' }, { status: 400 })

	const { error } = await supabase.from('subscription_plans').delete().eq('plan_id', planId)
	if (error) return json({ error: error.message }, { status: 500 })

	await logAdminAction({
		ctx,
		action: 'subscription_plans.delete',
		target_type: 'subscription_plan',
		target_id: planId,
		before_state: null,
		after_state: null,
		meta: { module: 'subscriptions' },
		req,
	})

	return json({ ok: true })
}

type PatchPlanBody = {
	plan_id: string
	audience?: 'consumer' | 'artist' | 'dj' | null
	name?: string
	price_mwk?: number
	billing_interval?: 'month' | 'week'
	coins_multiplier?: number
	ads_enabled?: boolean
	can_participate_battles?: boolean
	battle_priority?: 'none' | 'standard' | 'priority'
	analytics_level?: 'basic' | 'standard' | 'advanced'
	content_access?: 'limited' | 'standard' | 'exclusive'
	content_limit_ratio?: number | null
	featured_status?: boolean
	is_active?: boolean
	sort_order?: number | null
	features?: Record<string, unknown>
	perks?: Record<string, unknown> | null
	marketing?: Record<string, unknown> | null
	trial_eligible?: boolean
	trial_duration_days?: number | null
}

export async function PATCH(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as PatchPlanBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })

	const planId = asSubscriptionPlanId(body.plan_id)
	if (!planId) return json({ error: 'Invalid plan_id' }, { status: 400 })
	if ('audience' in body && body.audience !== undefined && body.audience != null) {
		const aud = String(body.audience).trim().toLowerCase()
		if (aud !== 'consumer' && aud !== 'artist' && aud !== 'dj') {
			return json({ error: 'Invalid audience' }, { status: 400 })
		}
	}

	// Free must remain active.
	if (planId === 'free' && body.is_active === false) {
		return json({ error: 'Free plan must remain active.' }, { status: 400 })
	}

	const patch: Record<string, unknown> = {}
	const allowedKeys: Array<keyof PatchPlanBody> = [
		'audience',
		'name',
		'price_mwk',
		'billing_interval',
		'coins_multiplier',
		'ads_enabled',
		'can_participate_battles',
		'battle_priority',
		'analytics_level',
		'content_access',
		'content_limit_ratio',
		'featured_status',
		'is_active',
		'sort_order',
		'features',
		'perks',
		'marketing',
		'trial_eligible',
		'trial_duration_days',
	]

	for (const k of allowedKeys) {
		if (k in body) (patch as any)[k] = (body as any)[k]
	}
	if (body.trial_eligible === false) {
		patch.trial_duration_days = 0
	} else if (body.trial_eligible === true && !('trial_duration_days' in body)) {
		patch.trial_duration_days = defaultTrialDurationDaysForPlanId(planId)
	} else if ('trial_duration_days' in body) {
		patch.trial_duration_days = Math.max(0, Number(body.trial_duration_days ?? 0) || 0)
	}
	patch.updated_at = new Date().toISOString()

	if (!Object.keys(patch).length) return json({ error: 'Nothing to update.' }, { status: 400 })

	// capture before state for auditing
	let before: any = null
	let beforeErr: any = null
	;({ data: before, error: beforeErr } = await supabase
		.from('subscription_plans')
		.select('audience,plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,is_active,sort_order,features,perks,marketing,trial_eligible,trial_duration_days')
		.eq('plan_id', planId)
		.maybeSingle())
	if (beforeErr && isMissingColumn(beforeErr, 'audience')) {
		;({ data: before } = await supabase
			.from('subscription_plans')
			.select('plan_id,name,price_mwk,billing_interval,coins_multiplier,ads_enabled,can_participate_battles,battle_priority,analytics_level,content_access,content_limit_ratio,featured_status,is_active,sort_order,features,perks,marketing,trial_eligible,trial_duration_days')
			.eq('plan_id', planId)
			.maybeSingle())
	}

	let updated: any = null
	let error: any = null
	;({ data: updated, error } = await supabase
		.from('subscription_plans')
		.update(patch)
		.eq('plan_id', planId)
		.select(SELECT_WITH_AUDIENCE)
		.single())
	if (error && isMissingColumn(error, 'audience')) {
		delete patch.audience
		;({ data: updated, error } = await supabase
			.from('subscription_plans')
			.update(patch)
			.eq('plan_id', planId)
			.select(SELECT_NO_AUDIENCE)
			.single())
	}

	if (error) return json({ error: error.message }, { status: 500 })

	await logAdminAction({
		ctx,
		action: 'subscription_plans.update',
		target_type: 'subscription_plan',
		target_id: planId,
		before_state: (before ?? null) as any,
		after_state: (updated ?? null) as any,
		meta: { module: 'subscriptions' },
		req,
	})

	return json({ ok: true, plan: updated as unknown as PlanRow })
}
