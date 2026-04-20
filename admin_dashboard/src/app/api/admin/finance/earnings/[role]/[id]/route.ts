import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import type { SupabaseClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'

type PatchBody = { action: 'set_frozen'; frozen: boolean; reason?: string }

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

export async function PATCH(req: Request, ctx: { params: Promise<{ role: string; id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_manage_finance') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

	const { role, id } = await ctx.params
	if (role !== 'artist' && role !== 'dj') return NextResponse.json({ error: 'Invalid role' }, { status: 400 })
	if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || body.action !== 'set_frozen') return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for finance actions (no anon fallback).' },
			{ status: 500 },
		)
	}
	const now = new Date().toISOString()

	// Upsert current state
	const { error: stateError } = await supabase.from('earnings_freeze_state').upsert(
		{
			beneficiary_type: role,
			beneficiary_id: id,
			frozen: !!body.frozen,
			reason: (body.reason ?? '').trim() || null,
			updated_by_email: adminCtx.admin.email,
			updated_at: now,
		},
		{ onConflict: 'beneficiary_type,beneficiary_id' },
	)

	if (stateError) return NextResponse.json({ error: stateError.message }, { status: 500 })

	// Append event history
	try {
		await supabase.from('earnings_freeze_events').insert({
			beneficiary_type: role,
			beneficiary_id: id,
			frozen: !!body.frozen,
			reason: (body.reason ?? '').trim() || null,
			admin_email: adminCtx.admin.email,
		})
	} catch {
		// best-effort
	}

	await tryLogFinance(supabase, {
		admin_email: adminCtx.admin.email,
		action: 'finance.earnings.set_frozen',
		target_type: `earnings_${role}`,
		target_id: id,
		meta: { frozen: !!body.frozen, reason: (body.reason ?? '').trim() || null },
	})

	return NextResponse.json({ ok: true })
}
