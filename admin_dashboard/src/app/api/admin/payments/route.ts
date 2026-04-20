export const runtime = 'nodejs'

import { json, requireAdmin } from '../_utils'
import { assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

function clampInt(raw: string | null, fallback: number, min: number, max: number): number {
	if (!raw) return fallback
	const n = Number(raw)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

type Kind = 'subscription_payments' | 'transactions'

export async function GET(req: Request) {
	const { ctx, res } = await requireAdmin()
	if (res) return res
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for payments/finance endpoints (no anon fallback).' },
			{ status: 500 },
		)
	}

	const url = new URL(req.url)
	const kind = ((url.searchParams.get('kind') ?? 'subscription_payments').trim().toLowerCase() ||
		'subscription_payments') as Kind
	if (kind !== 'subscription_payments' && kind !== 'transactions') {
		return json({ error: 'Invalid kind (use subscription_payments|transactions)' }, { status: 400 })
	}

	const limit = clampInt(url.searchParams.get('limit'), 200, 1, 500)
	const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10_000)
	const rangeTo = offset + limit - 1

	if (kind === 'transactions') {
		const type = (url.searchParams.get('type') ?? 'all').trim().toLowerCase()
		let q = supabase
			.from('transactions')
			.select('id,type,actor_type,actor_id,target_type,target_id,amount_mwk,coins,source,country_code,created_at')
			.order('created_at', { ascending: false })
			.range(offset, rangeTo)
		if (type && type !== 'all') q = q.eq('type', type)
		const { data, error } = await q
		if (error) return json({ error: error.message }, { status: 500 })
		return json({ ok: true, kind, items: data ?? [], limit, offset }, { headers: { 'cache-control': 'no-store' } })
	}

	const status = (url.searchParams.get('status') ?? 'all').trim().toLowerCase()
	const provider = (url.searchParams.get('provider') ?? 'all').trim().toLowerCase()
	const userId = (url.searchParams.get('user_id') ?? '').trim()

	let q = supabase
		.from('subscription_payments')
		.select(
			'id,provider,provider_reference,status,user_id,plan_id,amount_mwk,currency,country_code,user_subscription_id,created_at,updated_at',
		)
		.order('created_at', { ascending: false })
		.range(offset, rangeTo)

	if (status && status !== 'all') q = q.eq('status', status)
	if (provider && provider !== 'all') q = q.eq('provider', provider)
	if (userId) q = q.eq('user_id', userId)

	const { data, error } = await q
	if (error) return json({ error: error.message }, { status: 500 })

	return json({ ok: true, kind, items: data ?? [], limit, offset }, { headers: { 'cache-control': 'no-store' } })
}
