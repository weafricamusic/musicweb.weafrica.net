import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, {
		...(init ?? {}),
		headers: {
			'cache-control': 'no-store',
			...(init?.headers ?? {}),
		},
	})
}

const DEFAULT_GENRES = [
	'R&B',
	'Afrobeats',
	'Amapiano',
	'Hip-Hop',
	'Gospel',
	'Dancehall',
	'Reggae',
	'House',
	'EDM',
	'Pop',
	'Rock',
	'Jazz',
	'Traditional',
	'Other',
]

function isMissingTableError(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { code?: unknown; message?: unknown; details?: unknown; hint?: unknown }
	const code = typeof e.code === 'string' ? e.code : null
	if (code === '42P01' || code === 'PGRST205') return true
	const msg = [e.message, e.details, e.hint].map((x) => (typeof x === 'string' ? x : '')).join(' ').toLowerCase()
	return msg.includes('does not exist') || msg.includes('could not find the table')
}

function uniqStrings(values: unknown[]): string[] {
	const out: string[] = []
	const seen = new Set<string>()
	for (const v of values) {
		if (typeof v !== 'string') continue
		const s = v.trim()
		if (!s) continue
		const key = s.toLowerCase()
		if (seen.has(key)) continue
		seen.add(key)
		out.push(s)
	}
	return out
}

export async function GET() {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		// Best-fit permission for content management in the current RBAC schema.
		if (!adminCtx.permissions.can_manage_artists && adminCtx.admin.role !== 'super_admin' && adminCtx.admin.role !== 'operations_admin') {
			return json({ error: 'Forbidden' }, { status: 403 })
		}
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json({ ok: true, source: 'fallback', genres: DEFAULT_GENRES, categories: [] })
	}

	let genres: string[] | null = null
	let categories: string[] | null = null

	try {
		const { data, error } = await supabase
			.from('genres')
			.select('name')
			.eq('is_active', true)
			.order('name', { ascending: true })
			.limit(500)
		if (error) throw error
		genres = uniqStrings((data ?? []).map((r: any) => r?.name))
	} catch (e) {
		if (!isMissingTableError(e)) genres = []
	}

	try {
		const { data, error } = await supabase
			.from('categories')
			.select('name')
			.eq('is_active', true)
			.order('name', { ascending: true })
			.limit(500)
		if (error) throw error
		categories = uniqStrings((data ?? []).map((r: any) => r?.name))
	} catch (e) {
		if (!isMissingTableError(e)) categories = []
	}

	// If tables are missing, fall back to distinct values seen in songs + defaults.
	if (genres === null || categories === null) {
		let songValues: unknown[] = []
		try {
			const { data } = await supabase
				.from('songs')
				.select('genre,primary_genre,category')
				.limit(500)
			songValues = (data ?? []).flatMap((r: any) => [r?.genre, r?.primary_genre, r?.category])
		} catch {
			songValues = []
		}

		const distinct = uniqStrings(songValues)
		const mergedGenres = uniqStrings([...DEFAULT_GENRES, ...distinct])
		return json({ ok: true, source: 'fallback', genres: mergedGenres, categories: distinct })
	}

	return json({ ok: true, source: 'db', genres, categories })
}
