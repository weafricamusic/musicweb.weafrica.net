import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type PlanId = 'free' | 'premium'

type PromotionPublicRow = {
	id: string
	title: string
	description: string | null
	image_url: string
	target_plan: 'all' | 'free' | 'premium'
	priority: number
	starts_at: string | null
	ends_at: string | null
	created_at: string
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function asPlanId(raw: string): PlanId | null {
	const v = raw.trim()
	if (v === 'free' || v === 'premium') return v
	return null
}

/**
 * Public endpoint intended for the consumer app.
 *
 * Returns only promotions that are:
 * - is_active = true
 * - within the optional scheduling window
 * - targeted to the provided plan (or all)
 *
 * Query params:
 * - plan_id: free | premium (optional)
 */
export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const planRaw = req.nextUrl.searchParams.get('plan_id')
	const planId = planRaw ? asPlanId(planRaw) : null
	if (planRaw && !planId) return json({ error: 'Invalid plan_id' }, { status: 400 })

	const nowIso = new Date().toISOString()

	let query = supabase
		.from('promotions')
		.select('id,title,description,image_url,target_plan,priority,starts_at,ends_at,created_at')
		.eq('is_active', true)
		.or(`starts_at.is.null,starts_at.lte.${nowIso}`)
		.or(`ends_at.is.null,ends_at.gte.${nowIso}`)
		.order('priority', { ascending: false })
		.order('created_at', { ascending: false })
		.limit(50)

	if (planId) {
		query = query.in('target_plan', ['all', planId])
	}

	const { data, error } = await query
	if (error) return json({ error: String(error.message ?? 'Query failed') }, { status: 500 })

	return NextResponse.json(
		{ ok: true, promotions: (data ?? []) as unknown as PromotionPublicRow[] },
		{
			headers: {
				'cache-control': 'no-store',
			},
		},
	)
}
