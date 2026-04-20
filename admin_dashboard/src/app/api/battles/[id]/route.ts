import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(_req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
	const { id } = await ctx.params
	if (!id) return json({ error: 'Missing id' }, { status: 400 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ ok: true, battle: null, warning: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' },
			{ headers: { 'cache-control': 'no-store' } },
		)
	}

	const { data, error } = await supabase
		.from('live_streams')
		.select('id,channel_name,host_type,host_id,viewer_count,stream_type,status,started_at,ended_at,region,created_at')
		.eq('stream_type', 'battle')
		.eq('id', id)
		.maybeSingle()

	if (error) return json({ error: error.message }, { status: 500 })
	if (!data) return json({ error: 'Not found' }, { status: 404 })

	return NextResponse.json({ ok: true, battle: data }, { headers: { 'cache-control': 'no-store' } })
}
