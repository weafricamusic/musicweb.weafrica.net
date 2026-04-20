import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

type PromotionRow = {
	id: string
	title: string
	description: string | null
	image_url: string
	target_plan: 'all' | 'free' | 'premium'
	is_active: boolean
	priority: number
	starts_at: string | null
	ends_at: string | null
	created_at: string
	updated_at: string
}

function asTargetPlan(raw: unknown): PromotionRow['target_plan'] | null {
	const v = String(raw ?? '')
	if (v === 'all' || v === 'free' || v === 'premium') return v
	return null
}

type UpdateBody = Partial<{
	title: string
	description: string | null
	image_url: string
	target_plan: 'all' | 'free' | 'premium'
	is_active: boolean
	priority: number
	starts_at: string | null
	ends_at: string | null
}>

export async function GET(_req: Request, ctxArgs: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { id } = await ctxArgs.params
	const promotionId = String(id ?? '').trim()
	if (!promotionId) return json({ ok: false, error: 'Missing id' }, { status: 400 })

	const { data, error } = await supabase
		.from('promotions')
		.select('id,title,description,image_url,target_plan,is_active,priority,starts_at,ends_at,created_at,updated_at')
		.eq('id', promotionId)
		.maybeSingle()

	if (error) return json({ ok: false, error: String(error.message ?? 'Query failed') }, { status: 500 })
	if (!data) return json({ ok: false, error: 'Not found' }, { status: 404 })
	return json({ ok: true, data: data as unknown as PromotionRow })
}

export async function PUT(req: Request, ctxArgs: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { id } = await ctxArgs.params
	const promotionId = String(id ?? '').trim()
	if (!promotionId) return json({ ok: false, error: 'Missing id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as UpdateBody | null
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid body' }, { status: 400 })

	const { data: before } = await supabase
		.from('promotions')
		.select('id,title,description,image_url,target_plan,is_active,priority,starts_at,ends_at')
		.eq('id', promotionId)
		.maybeSingle()

	const patch: Record<string, unknown> = {}

	if ('title' in body) {
		const title = String(body.title ?? '').trim()
		if (!title) return json({ ok: false, error: 'title is required' }, { status: 400 })
		patch.title = title
	}
	if ('description' in body) patch.description = body.description ?? null
	if ('image_url' in body) patch.image_url = String(body.image_url ?? '')
	if ('is_active' in body) patch.is_active = Boolean(body.is_active)
	if ('starts_at' in body) patch.starts_at = body.starts_at ?? null
	if ('ends_at' in body) patch.ends_at = body.ends_at ?? null
	if ('priority' in body) {
		const p = Number(body.priority)
		if (!Number.isFinite(p) || Number.isNaN(p)) return json({ ok: false, error: 'Invalid priority' }, { status: 400 })
		patch.priority = Math.trunc(p)
	}
	if ('target_plan' in body) {
		const t = asTargetPlan(body.target_plan)
		if (!t) return json({ ok: false, error: 'Invalid target_plan' }, { status: 400 })
		patch.target_plan = t
	}

	if (!Object.keys(patch).length) return json({ ok: false, error: 'No changes' }, { status: 400 })

	const { data: updated, error } = await supabase
		.from('promotions')
		.update(patch)
		.eq('id', promotionId)
		.select('id,title,description,image_url,target_plan,is_active,priority,starts_at,ends_at,created_at,updated_at')
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Update failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'promotions.update',
		target_type: 'promotion',
		target_id: promotionId,
		before_state: (before ?? null) as unknown as Record<string, unknown> | null,
		after_state: (updated ?? null) as unknown as Record<string, unknown> | null,
		meta: { module: 'promotions' },
		req,
	})

	return json({ ok: true, data: updated as unknown as PromotionRow })
}
