import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { asSubscriptionPlanId, getEquivalentSubscriptionPlanIds } from '@/lib/subscription/plans'

export const runtime = 'nodejs'

type PromotionPublicRow = {
	id: string
	target_plan_id: string | null
	title: string | null
	body: string
	starts_at: string | null
	ends_at: string | null
	created_at: string
}

type ContentPromotionRow = {
	id: string
	title: string
	description: string | null
	target_plan: 'all' | 'starter' | 'pro' | 'elite' | 'free' | 'premium' | 'platinum'
	is_active: boolean
	starts_at: string | null
	ends_at: string | null
	created_at: string
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

/**
 * Public endpoint intended for the consumer app.
 *
 * Returns only promotions that are:
 * - status = published
 * - within the optional scheduling window
 * - targeted to the provided plan (or all)
 *
 * Query params:
 * - plan_id: free | premium | platinum | ... (legacy aliases accepted)
 */
export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const planRaw = req.nextUrl.searchParams.get('plan_id')
	const rawPlanId = planRaw ? asSubscriptionPlanId(planRaw) : null
	if (planRaw && !rawPlanId) return json({ error: 'Invalid plan_id' }, { status: 400 })
	const planIds = rawPlanId ? getEquivalentSubscriptionPlanIds(rawPlanId) : []

	const nowIso = new Date().toISOString()

	let query = supabase
		.from('subscription_promotions')
		.select('id,target_plan_id,title,body,starts_at,ends_at,created_at')
		.eq('status', 'published')
		.or(`starts_at.is.null,starts_at.lte.${nowIso}`)
		.or(`ends_at.is.null,ends_at.gte.${nowIso}`)
		.order('created_at', { ascending: false })
		.limit(50)

	// If a plan is provided, include promotions targeting that plan or all (null).
	if (planIds.length) {
		query = query.or(`target_plan_id.is.null,${planIds.map((id) => `target_plan_id.eq.${id}`).join(',')}`)
	}

	const [{ data: subscriptionPromotions, error: subscriptionError }, { data: contentPromotions, error: contentError }] = await Promise.all([
		query,
		(() => {
			let contentQuery = supabase
				.from('promotions')
				.select('id,title,description,target_plan,is_active,starts_at,ends_at,created_at')
				.eq('is_active', true)
				.or(`starts_at.is.null,starts_at.lte.${nowIso}`)
				.or(`ends_at.is.null,ends_at.gte.${nowIso}`)
				.order('created_at', { ascending: false })
				.limit(50)

			if (planIds.length) {
				contentQuery = contentQuery.in('target_plan', ['all', ...planIds])
			}
			return contentQuery
		})(),
	])

	if (subscriptionError) return json({ error: String(subscriptionError.message ?? 'Query failed') }, { status: 500 })
	if (contentError) return json({ error: String(contentError.message ?? 'Query failed') }, { status: 500 })

	const mappedContent = ((contentPromotions ?? []) as unknown as ContentPromotionRow[]).map<PromotionPublicRow>((row) => ({
		id: row.id,
		target_plan_id: row.target_plan === 'all' ? null : row.target_plan,
		title: row.title,
		body: String(row.description ?? row.title ?? '').trim() || row.title,
		starts_at: row.starts_at ?? null,
		ends_at: row.ends_at ?? null,
		created_at: row.created_at,
	}))

	const combined = ([...(((subscriptionPromotions ?? []) as unknown as PromotionPublicRow[]) ?? []), ...mappedContent] as PromotionPublicRow[])
		.filter((p) => Boolean(p.id))
		.sort((a, b) => {
			const ad = Date.parse(a.created_at)
			const bd = Date.parse(b.created_at)
			if (Number.isFinite(ad) && Number.isFinite(bd)) return bd - ad
			return String(b.created_at).localeCompare(String(a.created_at))
		})
		.slice(0, 50)

	return NextResponse.json(
		{ ok: true, promotions: combined },
		{
			headers: {
				// These promos can change quickly while testing; avoid stale results.
				'cache-control': 'no-store',
			},
		},
	)
}
