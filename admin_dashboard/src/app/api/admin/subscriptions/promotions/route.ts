import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { asSubscriptionPlanId } from '@/lib/subscription/plans'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

type PromotionRow = {
	id: string
	target_plan_id: string | null
	title: string | null
	body: string
	status: 'draft' | 'published' | 'archived'
	starts_at: string | null
	ends_at: string | null
	created_by: string | null
	created_at: string
	updated_at: string
}

function mapSupabaseError(err: any): string {
	const message = String(err?.message ?? 'Unknown error')
	const code = String(err?.code ?? '')
	const isMissingTable =
		code === '42P01' ||
		code === 'PGRST106' ||
		message.includes("Could not find the table 'public.subscription_promotions'") ||
		message.toLowerCase().includes('schema cache')

	if (isMissingTable) {
		return [
			"Missing table: public.subscription_promotions.",
			"Apply the migration supabase/migrations/20260114130000_subscriptions_admin_setup.sql to your Supabase project, then reload the schema cache (SQL: NOTIFY pgrst, 'reload schema';).",
		].join(' ')
	}

	return message
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
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

	const { data, error } = await supabase
		.from('subscription_promotions')
		.select('id,target_plan_id,title,body,status,starts_at,ends_at,created_by,created_at,updated_at')
		.order('created_at', { ascending: false })
		.limit(100)
	if (error) return json({ error: mapSupabaseError(error) }, { status: 500 })
	return json({ ok: true, promotions: (data ?? []) as unknown as PromotionRow[] })
}

type CreateBody = {
	target_plan_id?: string | null
	title?: string | null
	body: string
	status?: 'draft' | 'published' | 'archived'
	starts_at?: string | null
	ends_at?: string | null
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

	const body = (await req.json().catch(() => null)) as CreateBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })
	const text = String(body.body ?? '').trim()
	if (!text) return json({ error: 'body is required' }, { status: 400 })

	const targetRaw = body.target_plan_id ?? null
	const targetPlanId = targetRaw == null ? null : asSubscriptionPlanId(targetRaw)
	if (targetRaw != null && !targetPlanId) return json({ error: 'Invalid target_plan_id' }, { status: 400 })

	const nowIso = new Date().toISOString()
	const payload = {
		target_plan_id: targetPlanId,
		title: body.title ?? null,
		body: text,
		status: body.status ?? 'published',
		starts_at: body.starts_at ?? null,
		ends_at: body.ends_at ?? null,
		created_by: ctx.admin.email ?? null,
		updated_at: nowIso,
	}

	const { data: created, error } = await supabase
		.from('subscription_promotions')
		.insert(payload)
		.select('id,target_plan_id,title,body,status,starts_at,ends_at,created_by,created_at,updated_at')
		.single()
	if (error) return json({ error: mapSupabaseError(error) }, { status: 500 })

	await logAdminAction({
		ctx,
		action: 'subscription_promotions.create',
		target_type: 'subscription_promotion',
		target_id: String((created as any)?.id ?? ''),
		before_state: null,
		after_state: created as any,
		meta: { module: 'subscriptions' },
		req,
	})

	return json({ ok: true, promotion: created as unknown as PromotionRow })
}

type PatchBody = {
	id: string
	target_plan_id?: string | null
	title?: string | null
	body?: string
	status?: 'draft' | 'published' | 'archived'
	starts_at?: string | null
	ends_at?: string | null
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

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })
	const id = String(body.id ?? '').trim()
	if (!id) return json({ error: 'id is required' }, { status: 400 })

	const { data: before } = await supabase
		.from('subscription_promotions')
		.select('id,target_plan_id,title,body,status,starts_at,ends_at,created_by')
		.eq('id', id)
		.maybeSingle()

	const patch: Record<string, unknown> = { updated_at: new Date().toISOString() }
	if ('title' in body) patch.title = body.title ?? null
	if ('body' in body) patch.body = body.body == null ? undefined : String(body.body)
	if ('status' in body) patch.status = body.status
	if ('starts_at' in body) patch.starts_at = body.starts_at ?? null
	if ('ends_at' in body) patch.ends_at = body.ends_at ?? null
	if ('target_plan_id' in body) {
		const targetRaw = body.target_plan_id ?? null
		const targetPlanId = targetRaw == null ? null : asSubscriptionPlanId(targetRaw)
		if (targetRaw != null && !targetPlanId) return json({ error: 'Invalid target_plan_id' }, { status: 400 })
		patch.target_plan_id = targetPlanId
	}

	const { data: updated, error } = await supabase
		.from('subscription_promotions')
		.update(patch)
		.eq('id', id)
		.select('id,target_plan_id,title,body,status,starts_at,ends_at,created_by,created_at,updated_at')
		.single()
	if (error) return json({ error: mapSupabaseError(error) }, { status: 500 })

	await logAdminAction({
		ctx,
		action: 'subscription_promotions.update',
		target_type: 'subscription_promotion',
		target_id: id,
		before_state: (before ?? null) as any,
		after_state: (updated ?? null) as any,
		meta: { module: 'subscriptions' },
		req,
	})

	return json({ ok: true, promotion: updated as unknown as PromotionRow })
}
