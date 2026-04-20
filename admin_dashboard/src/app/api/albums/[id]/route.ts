import { NextResponse } from 'next/server'
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
	return (
		code === '42703' ||
		msg.includes(`'${column.toLowerCase()}' column`) ||
		msg.includes(`\"${column.toLowerCase()}\"`) ||
		msg.includes(`${column.toLowerCase()} column`) ||
		msg.includes(`column ${column.toLowerCase()} does not exist`)
	)
}

/**
 * Public album details.
 * Only returns if the album is published + public.
 */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
	const supabase = tryCreateSupabasePublicClient()
	if (!supabase) {
		return json(
			{ error: 'Server not configured (missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY).' },
			{ status: 500 },
		)
	}

	const { id } = await params
	const albumId = String(id ?? '').trim()
	if (!albumId) return json({ error: 'Missing id' }, { status: 400 })

	const nowIso = new Date().toISOString()
	let { data, error } = await supabase
		.from('albums')
		.select('id,artist_id,title,description,cover_url,visibility,release_at,published_at,price_mwk,price_coins,created_at,updated_at')
		.eq('id', albumId)
		.eq('visibility', 'public')
		.eq('is_active', true)
		.not('published_at', 'is', null)
		.lte('release_at', nowIso)
		.limit(1)
		.maybeSingle()

	if (error && isMissingColumn(error, 'is_active')) {
		// Retry without is_active constraint.
		const res2 = await supabase
			.from('albums')
			.select('id,artist_id,title,description,cover_url,visibility,release_at,published_at,price_mwk,price_coins,created_at,updated_at')
			.eq('id', albumId)
			.eq('visibility', 'public')
			.not('published_at', 'is', null)
			.lte('release_at', nowIso)
			.limit(1)
			.maybeSingle()
		data = res2.data
		error = res2.error
	}

	if (error) return json({ error: error.message }, { status: 500 })
	if (!data) return json({ error: 'Not found' }, { status: 404 })

	return NextResponse.json({ ok: true, album: data }, { headers: { 'cache-control': 'no-store' } })
}
