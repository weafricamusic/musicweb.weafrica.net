import { NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function POST(req: Request) {
	const secret = (process.env.SUBSCRIPTIONS_CRON_SECRET ?? '').trim()
	if (!secret) return json({ error: 'Server not configured (missing SUBSCRIPTIONS_CRON_SECRET).' }, { status: 503 })

	const provided = (req.headers.get('x-cron-secret') ?? '').trim()
	if (!provided || provided !== secret) return json({ error: 'Unauthorized' }, { status: 401 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 503 })

	const nowIso = new Date().toISOString()

	// Expire paid plans that have passed ends_at.
	const { data: rows, error } = await supabase
		.from('user_subscriptions')
		.select('id')
		.eq('status', 'active')
		.not('ends_at', 'is', null)
		.lt('ends_at', nowIso)
		.limit(500)

	if (error) return json({ error: error.message }, { status: 500 })

	const ids = (rows ?? []).map((r: any) => Number(r.id)).filter((n) => Number.isFinite(n))
	if (!ids.length) return json({ ok: true, expired: 0 })

	const { error: updErr } = await supabase
		.from('user_subscriptions')
		.update({ status: 'expired', auto_renew: false, updated_at: nowIso })
		.in('id', ids)

	if (updErr) return json({ error: updErr.message }, { status: 500 })
	return json({ ok: true, expired: ids.length })
}
