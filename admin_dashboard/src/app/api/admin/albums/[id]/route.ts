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

function normalizeInt(value: unknown): number | null {
	const raw = String(value ?? '').trim()
	if (!raw) return null
	const n = Number(raw)
	if (!Number.isFinite(n)) return null
	return Math.trunc(n)
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

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { id } = await params
	const albumId = String(id ?? '').trim()
	if (!albumId) return json({ error: 'Missing id' }, { status: 400 })

	const { data, error } = await supabase.from('albums').select('*').eq('id', albumId).limit(1).maybeSingle<any>()
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "albums table not found. Apply the albums migration, then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}
	if (!data) return json({ error: 'Not found' }, { status: 404 })

	return json({ ok: true, album: data }, { status: 200 })
}

export async function PATCH(req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { id } = await params
	const albumId = String(id ?? '').trim()
	if (!albumId) return json({ error: 'Missing id' }, { status: 400 })

	let body: any
	try {
		body = await req.json()
	} catch {
		body = null
	}
	if (!body || typeof body !== 'object') return json({ error: 'Invalid JSON body' }, { status: 400 })

	const update: Record<string, any> = {}
	const title = normalizeText(body.title, 140)
	if (title) update.title = title
	const description = normalizeText(body.description, 2000)
	if (description != null) update.description = description
	const coverUrl = normalizeText(body.cover_url, 600)
	if (coverUrl != null) update.cover_url = coverUrl

	const visibility = normalizeVisibility(body.visibility)
	if (visibility) update.visibility = visibility

	const releaseAt = normalizeIsoDate(body.release_at)
	if (releaseAt != null) update.release_at = releaseAt

	const priceMwk = normalizeInt(body.price_mwk)
	if (priceMwk != null) update.price_mwk = Math.max(0, Math.min(1_000_000_000, priceMwk))

	const priceCoins = normalizeInt(body.price_coins)
	if (priceCoins != null) update.price_coins = Math.max(0, Math.min(1_000_000_000, priceCoins))

	if (typeof body.is_active === 'boolean') update.is_active = body.is_active

	// Publishing convenience: when making public and already releasable, set published_at.
	if (update.visibility === 'public') {
		const rel = update.release_at ? new Date(update.release_at).getTime() : Date.now()
		if (!Number.isNaN(rel) && rel <= Date.now()) update.published_at = new Date().toISOString()
	}

	if (!Object.keys(update).length) return json({ error: 'No changes' }, { status: 400 })
	update.updated_at = new Date().toISOString()

	const { error } = await supabase.from('albums').update(update).eq('id', albumId)
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "albums table not found. Apply the albums migration, then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	return json({ ok: true }, { status: 200 })
}
