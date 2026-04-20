import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

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

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function asTargetPlan(raw: unknown): PromotionRow['target_plan'] | null {
	const v = String(raw ?? '')
	if (v === 'all' || v === 'free' || v === 'premium') return v
	return null
}

type CreateBody = {
	title: string
	description?: string | null
	image_url?: string
	banner_url?: string        // new field — aliases image_url
	target_plan?: 'all' | 'free' | 'premium'
	is_active?: boolean
	status?: string            // draft | scheduled | active | paused | ended
	priority?: number
	starts_at?: string | null
	ends_at?: string | null
	// Promotion engine fields (migration 20260316130000)
	promotion_type?: string
	target_id?: string | null
	country?: string | null
	surface?: string | null
	start_date?: string | null
	end_date?: string | null
	source_type?: string
}

export async function GET() {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data, error } = await supabase
		.from('promotions')
		.select('id,title,description,image_url,target_plan,is_active,priority,starts_at,ends_at,created_at,updated_at')
		.order('created_at', { ascending: false })
		.limit(200)

	if (error) return json({ ok: false, error: String(error.message ?? 'Query failed') }, { status: 500 })
	return json({ ok: true, data: (data ?? []) as unknown as PromotionRow[] })
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as CreateBody | null
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid body' }, { status: 400 })

	const title = String(body.title ?? '').trim()
	if (!title) return json({ ok: false, error: 'title is required' }, { status: 400 })

	const target = body.target_plan == null ? 'all' : asTargetPlan(body.target_plan)
	if (!target) return json({ ok: false, error: 'Invalid target_plan' }, { status: 400 })

	const priorityRaw = body.priority
	const priority = priorityRaw == null ? 0 : Number(priorityRaw)
	if (!Number.isFinite(priority) || Number.isNaN(priority)) return json({ ok: false, error: 'Invalid priority' }, { status: 400 })

	// Resolve banner: accept either banner_url (new) or image_url (legacy)
	const bannerUrl = String(body.banner_url ?? body.image_url ?? '').trim()

	// Resolve is_active from status field or explicit is_active flag
	const statusField = String(body.status ?? '').trim().toLowerCase() || null
	const isActive = statusField ? statusField === 'active' : Boolean(body.is_active ?? false)

	// Dates: support both legacy (starts_at/ends_at) and new (start_date/end_date)
	const startDate = (body.start_date ?? body.starts_at) ?? null
	const endDate = (body.end_date ?? body.ends_at) ?? null

	const payload = {
		title,
		description: body.description ?? null,
		image_url: bannerUrl,
		banner_url: bannerUrl || null,
		target_plan: target,
		is_active: isActive,
		priority: Math.trunc(priority),
		starts_at: startDate,
		ends_at: endDate,
		// Promotion engine fields (present only after migration 20260316130000)
		...(body.promotion_type != null && { promotion_type: String(body.promotion_type).trim() }),
		...(body.target_id != null && { target_id: String(body.target_id).trim() || null }),
		...(body.country != null && { country: String(body.country).trim().toUpperCase().slice(0, 2) || null }),
		...(body.surface != null && { surface: String(body.surface).trim() || null }),
		...(statusField != null && { status: statusField }),
		...(body.start_date != null && { start_date: body.start_date }),
		...(body.end_date != null && { end_date: body.end_date }),
		source_type: String(body.source_type ?? 'admin').trim() || 'admin',
	}

	const { data: created, error } = await supabase
		.from('promotions')
		.insert(payload)
		.select('id,title,description,image_url,target_plan,is_active,priority,starts_at,ends_at,created_at,updated_at')
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Insert failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'promotions.create',
		target_type: 'promotion',
		target_id: String((created as { id?: string } | null)?.id ?? ''),
		before_state: null,
		after_state: created as unknown as Record<string, unknown>,
		meta: { module: 'promotions' },
		req,
	})

	return json({ ok: true, data: created as unknown as PromotionRow })
}
