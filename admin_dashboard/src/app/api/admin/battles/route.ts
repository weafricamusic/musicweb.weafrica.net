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

type Status = 'live' | 'ended' | 'all'

export async function GET(req: Request) {
	const { ctx, res } = await requireAdmin()
	if (res) return res
	try {
		assertPermission(ctx, 'can_stop_streams')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for battles moderation (no anon fallback).' },
			{ status: 500 },
		)
	}

	const url = new URL(req.url)
	const status = ((url.searchParams.get('status') ?? 'all').trim().toLowerCase() || 'all') as Status
	if (status !== 'live' && status !== 'ended' && status !== 'all') {
		return json({ error: 'Invalid status (use live|ended|all)' }, { status: 400 })
	}

	const limit = clampInt(url.searchParams.get('limit'), 200, 1, 500)
	const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10_000)
	const rangeTo = offset + limit - 1

	let q = supabase
		.from('live_streams')
		.select('id,channel_name,host_type,host_id,viewer_count,stream_type,status,started_at,ended_at,region,created_at')
		.eq('stream_type', 'battle')
		.order('started_at', { ascending: false })
		.range(offset, rangeTo)

	if (status !== 'all') q = q.eq('status', status)

	const { data, error } = await q
	if (error) return json({ error: error.message }, { status: 500 })

	return json(
		{ ok: true, battles: data ?? [], limit, offset },
		{ headers: { 'cache-control': 'no-store' } },
	)
}
