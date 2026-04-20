import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function PATCH(req: Request, ctxArgs: { params: Promise<{ id: string }> }) {
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

	const { data: before } = await supabase
		.from('promotions')
		.select('id,is_active')
		.eq('id', promotionId)
		.maybeSingle()

	const { data: updated, error } = await supabase
		.from('promotions')
		.update({ is_active: true })
		.eq('id', promotionId)
		.select('id,title,description,image_url,target_plan,is_active,priority,starts_at,ends_at,created_at,updated_at')
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Activate failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'promotions.activate',
		target_type: 'promotion',
		target_id: promotionId,
		before_state: (before ?? null) as unknown as Record<string, unknown> | null,
		after_state: (updated ?? null) as unknown as Record<string, unknown> | null,
		meta: { module: 'promotions' },
		req,
	})

	return json({ ok: true })
}
