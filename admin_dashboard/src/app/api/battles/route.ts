import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function clampInt(raw: string | null, fallback: number, min: number, max: number): number {
	if (!raw) return fallback
	const n = Number(raw)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

type Status = 'live' | 'ended' | 'all'

export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ ok: true, battles: [], warning: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' },
			{ headers: { 'cache-control': 'no-store' } },
		)
	}

	const url = req.nextUrl
	const status = ((url.searchParams.get('status') ?? 'live').trim().toLowerCase() || 'live') as Status
	if (status !== 'live' && status !== 'ended' && status !== 'all') {
		return json({ error: 'Invalid status (use live|ended|all)' }, { status: 400 })
	}

	const limit = clampInt(url.searchParams.get('limit'), 50, 1, 200)
	const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10_000)
	const rangeTo = offset + limit - 1

	let query = supabase
		.from('live_streams')
		.select('id,channel_name,host_type,host_id,viewer_count,stream_type,status,started_at,ended_at,region,created_at')
		.eq('stream_type', 'battle')
		.order('started_at', { ascending: false })
		.range(offset, rangeTo)

	if (status !== 'all') query = query.eq('status', status)

	const { data, error } = await query
	if (error) {
		// If the project hasn't applied the live_streams migration yet, don't hard-fail consumers.
		const message = String(error.message ?? '')
		const missing = /schema cache|could not find|does not exist|PGRST205/i.test(message)
		if (missing) {
			return NextResponse.json(
				{ ok: true, battles: [], warning: 'live_streams table not found (apply live streams migration).' },
				{ headers: { 'cache-control': 'no-store' } },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	return NextResponse.json(
		{ ok: true, battles: data ?? [], limit, offset },
		{ headers: { 'cache-control': 'no-store' } },
	)
}
