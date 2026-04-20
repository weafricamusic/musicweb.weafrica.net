import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabasePublicClient } from '@/lib/supabase/public'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function isMissingColumn(err: unknown, column: string): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { message?: unknown; code?: unknown; details?: unknown; hint?: unknown }
	const msg = [e.message, e.details, e.hint]
		.map((x) => (typeof x === 'string' ? x : ''))
		.join(' ')
		.toLowerCase()
	const code = typeof e.code === 'string' ? e.code : ''
	return code === '42703' || msg.includes(`'${column.toLowerCase()}' column`) || msg.includes(`\"${column.toLowerCase()}\"`) || msg.includes(`${column.toLowerCase()} column`) || msg.includes(`column ${column.toLowerCase()} does not exist`)
}

function clampInt(raw: string | null, fallback: number, min: number, max: number): number {
	if (!raw) return fallback
	const n = Number(raw)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

/**
 * Public albums list.
 * Only returns albums that are published + visible to consumers.
 */
export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabasePublicClient()
	if (!supabase) {
		return json(
			{ error: 'Server not configured (missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY).' },
			{ status: 500 },
		)
	}

	const url = req.nextUrl
	const limit = clampInt(url.searchParams.get('limit'), 50, 1, 200)
	const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10_000)
	const artistId = (url.searchParams.get('artist_id') ?? '').trim()

	const rangeTo = offset + limit - 1
	const nowIso = new Date().toISOString()

	// NOTE: This assumes RLS allows reading these columns for public albums.
	let q = supabase
		.from('albums')
		.select('id,artist_id,title,description,cover_url,visibility,release_at,published_at,price_mwk,price_coins,created_at,updated_at')
		.eq('visibility', 'public')
		.not('published_at', 'is', null)
		.lte('release_at', nowIso)
		.order('published_at', { ascending: false })
		.range(offset, rangeTo)

	// Older DBs / stale PostgREST schema cache may not expose `is_active`.
	// Prefer filtering by it when available.
	q = q.eq('is_active', true)

	if (artistId) q = q.eq('artist_id', artistId)

	let { data, error } = await q
	if (error && isMissingColumn(error, 'is_active')) {
		// Retry without the is_active constraint.
		let q2 = supabase
			.from('albums')
			.select('id,artist_id,title,description,cover_url,visibility,release_at,published_at,price_mwk,price_coins,created_at,updated_at')
			.eq('visibility', 'public')
			.not('published_at', 'is', null)
			.lte('release_at', nowIso)
			.order('published_at', { ascending: false })
			.range(offset, rangeTo)
		if (artistId) q2 = q2.eq('artist_id', artistId)
		const res2 = await q2
		data = res2.data
		error = res2.error
	}
	if (error) return json({ error: error.message }, { status: 500 })

	return NextResponse.json(
		{ ok: true, albums: data ?? [], limit, offset },
		{ headers: { 'cache-control': 'no-store' } },
	)
}
