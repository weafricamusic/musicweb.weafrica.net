import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabasePublicClient } from '@/lib/supabase/public'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(_req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
	const { id } = await ctx.params
	if (!id) return json({ error: 'Missing id' }, { status: 400 })

	const supabase = tryCreateSupabasePublicClient()
	if (!supabase) {
		return json(
			{ error: 'Server not configured (missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY).' },
			{ status: 500 },
		)
	}

	const attempts = [
		'id,dj_name,avatar_url,bio,country,approved,status,blocked,created_at',
		'id,dj_name,approved,status,blocked,created_at',
		'id,dj_name,approved,created_at',
		'id,dj_name,created_at',
	] as const

	let lastError: unknown = null
	for (const select of attempts) {
		let query = supabase.from('djs').select(select).eq('id', id)
		// Defense-in-depth: enforce public-only visibility even if RLS isn't strict.
		query = query.eq('approved', true)
		query = query.eq('blocked', false)
		query = query.eq('status', 'active')
		const { data, error } = await query.maybeSingle()
		if (!error) {
			if (!data) return json({ error: 'Not found' }, { status: 404 })
			return NextResponse.json({ ok: true, dj: data }, { headers: { 'cache-control': 'no-store' } })
		}
		lastError = error
	}

	return json({ error: (lastError as any)?.message ?? 'Query failed' }, { status: 500 })
}
