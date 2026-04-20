import { NextResponse } from 'next/server'

import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function normalizeText(value: unknown, maxLen: number): string | null {
	const s = String(value ?? '').trim()
	if (!s) return null
	return s.length > maxLen ? s.slice(0, maxLen) : s
}

function normalizeVisibility(value: unknown): 'private' | 'unlisted' | 'public' | null {
	const v = String(value ?? '').trim().toLowerCase()
	if (!v) return null
	if (v === 'private' || v === 'unlisted' || v === 'public') return v
	return null
}

function normalizeInt(value: unknown, fallback: number, min: number, max: number): number {
	const raw = String(value ?? '').trim()
	if (!raw) return fallback
	const n = Number(raw)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

function normalizeIsoDate(value: unknown): string | null {
	const raw = String(value ?? '').trim()
	if (!raw) return null
	const d = new Date(raw)
	if (Number.isNaN(d.getTime())) return null
	return d.toISOString()
}

function isSchemaMissingError(message: string | undefined): boolean {
	const msg = String(message ?? '')
	return /schema cache|could not find the table|does not exist|PGRST205/i.test(msg)
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const url = new URL(req.url)
	const artistId = normalizeText(url.searchParams.get('artist_id'), 80)

	let q = supabase.from('albums').select('*').order('created_at', { ascending: false }).limit(200)
	if (artistId) q = q.eq('artist_id', artistId)

	const { data, error } = await q
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "albums table not found. Apply the albums migration, then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	return json({ ok: true, albums: data ?? [] }, { status: 200 })
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	let body: any
	try {
		body = await req.json()
	} catch {
		body = null
	}
	if (!body || typeof body !== 'object') return json({ error: 'Invalid JSON body' }, { status: 400 })

	const title = normalizeText(body.title, 140)
	const artistId = normalizeText(body.artist_id, 80)
	if (!title) return json({ error: 'Missing title' }, { status: 400 })
	if (!artistId) return json({ error: 'Missing artist_id' }, { status: 400 })

	const visibility = normalizeVisibility(body.visibility) ?? 'private'
	const releaseAt = normalizeIsoDate(body.release_at)
	const coverUrl = normalizeText(body.cover_url, 600)
	const description = normalizeText(body.description, 2000)
	const priceMwk = normalizeInt(body.price_mwk, 0, 0, 1_000_000_000)
	const priceCoins = normalizeInt(body.price_coins, 0, 0, 1_000_000_000)

	// If publishing immediately (public and release_at <= now), set published_at.
	let publishedAt: string | null = null
	if (visibility === 'public') {
		const now = Date.now()
		const rel = releaseAt ? new Date(releaseAt).getTime() : now
		if (!Number.isNaN(rel) && rel <= now) publishedAt = new Date().toISOString()
	}

	const payload = {
		title,
		artist_id: artistId,
		description,
		cover_url: coverUrl,
		visibility,
		release_at: releaseAt,
		published_at: publishedAt,
		price_mwk: priceMwk,
		price_coins: priceCoins,
		is_active: true,
		updated_at: new Date().toISOString(),
	}

	const { data, error } = await supabase.from('albums').insert(payload).select('id').single<any>()
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "albums table not found. Apply the albums migration, then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	return json({ ok: true, album_id: String(data?.id ?? '') }, { status: 200 })
}
