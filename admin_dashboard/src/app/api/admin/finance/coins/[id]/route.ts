import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import type { SupabaseClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'

type PatchBody = { action: 'set_status'; status: 'active' | 'disabled'; reason?: string }

async function tryLogFinance(
	supabase: SupabaseClient,
	input: {
		admin_email: string | null
		action: string
		target_type: string
		target_id: string
		meta?: Record<string, unknown>
	},
) {
	try {
		await supabase.from('admin_logs').insert({
			admin_email: input.admin_email,
			action: input.action,
			target_type: input.target_type,
			target_id: input.target_id,
			reason: (input.meta as any)?.reason ?? null,
			meta: input.meta ?? {},
		})
	} catch {
		// best-effort
	}
}

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_manage_finance') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

	const { id } = await ctx.params
	const coinId = Number(id)
	if (!Number.isFinite(coinId)) return NextResponse.json({ error: 'Invalid coin id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || body.action !== 'set_status') return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for finance actions (no anon fallback).' },
			{ status: 500 },
		)
	}
	const { error } = await supabase
		.from('coins')
		.update({ status: body.status, updated_at: new Date().toISOString() })
		.eq('id', coinId)

	if (error) return NextResponse.json({ error: error.message }, { status: 500 })

	await tryLogFinance(supabase, {
		admin_email: adminCtx.admin.email,
		action: 'finance.coin.set_status',
		target_type: 'coin',
		target_id: String(coinId),
		meta: { status: body.status, reason: body.reason ?? null },
	})

	return NextResponse.json({ ok: true })
}
