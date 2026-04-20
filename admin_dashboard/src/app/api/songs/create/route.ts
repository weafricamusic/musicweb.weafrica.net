import { NextResponse } from 'next/server'
import type { DecodedIdToken } from 'firebase-admin/auth'
import type { SupabaseClient } from '@supabase/supabase-js'

import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { isAdminEmailAllowed } from '@/lib/admin/allowlist'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function getBearerToken(req: Request): string | null {
	const raw = req.headers.get('authorization') || req.headers.get('Authorization')
	if (!raw) return null
	const m = raw.match(/^Bearer\s+(.+)$/i)
	return m ? m[1]!.trim() : null
}

function normalizeText(value: unknown, maxLen: number): string | null {
	const s = String(value ?? '').trim()
	if (!s) return null
	if (s.length > maxLen) return s.slice(0, maxLen)
	return s
}

function getErrorMessage(err: unknown): string {
	if (err instanceof Error) return err.message
	if (err && typeof err === 'object' && 'message' in err) {
		const v = (err as { message?: unknown }).message
		return String(v ?? '')
	}
	return String(err ?? '')
}

function getErrorCode(err: unknown): string {
	if (err && typeof err === 'object' && 'code' in err) {
		const v = (err as { code?: unknown }).code
		return String(v ?? '')
	}
	return ''
}

function findMissingColumn(message: string | undefined): string | null {
	const msg = String(message ?? '')
	let m = msg.match(/column \"([^\"]+)\" of relation/i)
	if (m?.[1]) return m[1]
	m = msg.match(/column \"([^\"]+)\" does not exist/i)
	if (m?.[1]) return m[1]
	m = msg.match(/could not find the '([^']+)' column/i)
	if (m?.[1]) return m[1]
	m = msg.match(/column (?:[a-z0-9_]+\.)?([a-z0-9_]+) does not exist/i)
	if (m?.[1]) return m[1]
	m = msg.match(/column ([a-z0-9_]+) does not exist/i)
	if (m?.[1]) return m[1]
	return null
}

function isMissingTableError(err: unknown): boolean {
	const message = getErrorMessage(err)
	const code = getErrorCode(err)
	return (
		code === '42P01' ||
		code === 'PGRST205' ||
		message.toLowerCase().includes('schema cache') ||
		message.toLowerCase().includes('could not find the table') ||
		/relations? .*songs.* does not exist/i.test(message)
	)
}

function isRowLevelSecurityError(err: unknown): boolean {
	const message = getErrorMessage(err).toLowerCase()
	const code = getErrorCode(err)
	return code === '42501' || message.includes('row-level security')
}

async function detectExistingColumns(args: {
	supabase: SupabaseClient
	table: string
	columns: string[]
}): Promise<{ columns: string[]; error: string | null }> {
	let cols = [...new Set(args.columns)].filter(Boolean)
	try {
		const smoke = await args.supabase.from(args.table).select('id').limit(1)
		if (smoke.error && isMissingTableError(smoke.error)) {
			return { columns: [], error: smoke.error.message ?? `Missing table ${args.table}` }
		}
	} catch {
		// ignore
	}

	for (let attempt = 0; attempt < 60; attempt++) {
		if (!cols.length) return { columns: [], error: null }
		const select = cols.join(',')
		const { error } = await args.supabase.from(args.table).select(select).limit(1)
		if (!error) return { columns: cols, error: null }
		const missing = findMissingColumn(error.message)
		if (missing && cols.includes(missing)) {
			cols = cols.filter((c) => c !== missing)
			continue
		}
		if (isMissingTableError(error)) {
			return { columns: [], error: error.message ?? `Missing table ${args.table}` }
		}
		return { columns: cols, error: error.message ?? 'Failed to detect columns' }
	}
	return { columns: cols, error: 'Failed to detect columns (too many attempts)' }
}

function filterPayloadByColumns(payload: Record<string, unknown>, columns: string[]): Record<string, unknown> {
	const allowed = new Set(columns)
	const out: Record<string, unknown> = {}
	for (const [k, v] of Object.entries(payload)) {
		if (!allowed.has(k)) continue
		if (v === undefined) continue
		out[k] = v
	}
	return out
}

async function insertSongAuto(
	supabase: SupabaseClient,
	payload: Record<string, unknown>,
): Promise<{ data: { id: string | number } | null; error: unknown | null; usedColumns: string[] }> {
	const detected = await detectExistingColumns({ supabase, table: 'songs', columns: Object.keys(payload) })
	if (detected.error) {
		return { data: null, error: new Error(detected.error), usedColumns: [] }
	}

	const usedColumns = detected.columns
	const current = filterPayloadByColumns(payload, usedColumns)

	const tryInsert = async () => await supabase.from('songs').insert(current).select('id').single<{ id: string | number }>()
	const res = await tryInsert()
	if (!res.error) return { data: res.data ?? null, error: null, usedColumns }
	return { data: null, error: res.error, usedColumns }
}

type Role = 'admin' | 'artist' | 'dj'

async function resolveUploaderRole(supabase: SupabaseClient, decoded: DecodedIdToken): Promise<Role | null> {
	const email = (decoded.email ?? '').trim().toLowerCase()
	if (email && isAdminEmailAllowed(email)) return 'admin'

	const uid = decoded.uid

	try {
		const { data, error } = await supabase
			.from('artists')
			.select('id,approved,status,blocked')
			.eq('firebase_uid', uid)
			.limit(1)
			.maybeSingle<any>()
		if (!error && data) {
			const blocked = data.blocked === true || String(data.status ?? '').toLowerCase() === 'blocked'
			if (blocked) return null
			return 'artist'
		}
	} catch {
		// ignore
	}

	try {
		const { data, error } = await supabase
			.from('djs')
			.select('id,approved,status,blocked')
			.eq('firebase_uid', uid)
			.limit(1)
			.maybeSingle<any>()
		if (!error && data) {
			const blocked = data.blocked === true || String(data.status ?? '').toLowerCase() === 'blocked'
			if (blocked) return null
			return 'dj'
		}
	} catch {
		// ignore
	}

	return null
}

export async function POST(req: Request) {
	const idToken = getBearerToken(req)
	if (!idToken) return json({ ok: false, error: 'Missing Authorization: Bearer <firebase_id_token>' }, { status: 401 })

	let decoded: DecodedIdToken
	try {
		const auth = getFirebaseAdminAuth()
		decoded = await auth.verifyIdToken(idToken)
	} catch {
		return json({ ok: false, error: 'Invalid auth token' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 500 })

	const role = await resolveUploaderRole(supabase, decoded)
	if (!role) return json({ ok: false, error: 'Forbidden (not an artist/dj/admin)' }, { status: 403 })

	const body = await req.json().catch(() => null)
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid JSON body' }, { status: 400 })

	const title = normalizeText((body as any).title ?? (body as any).name, 120)
	if (!title) return json({ ok: false, error: 'Missing title' }, { status: 400 })

	const audioUrl = normalizeText((body as any).audio_url ?? (body as any).audioUrl ?? (body as any).url, 2048)
	const thumbnailUrl = normalizeText((body as any).thumbnail_url ?? (body as any).thumbnailUrl ?? (body as any).image_url ?? (body as any).imageUrl, 2048)
	const duration = Number((body as any).duration ?? (body as any).duration_seconds ?? (body as any).durationSeconds ?? NaN)
	const durationVal = Number.isFinite(duration) && duration > 0 ? Math.round(duration) : null

	// Best-effort: resolve artist_id when the schema supports it.
	let artistId: string | null = null
	try {
		const { data } = await supabase
			.from('artists')
			.select('id')
			.eq('firebase_uid', decoded.uid)
			.limit(1)
			.maybeSingle<any>()
		artistId = data?.id ? String(data.id) : null
	} catch {
		artistId = null
	}

	const now = new Date().toISOString()
	const payload: Record<string, unknown> = {
		title,
		name: title,
		song_title: title,
		song_name: title,

		// Media
		audio_url: audioUrl,
		audio: audioUrl,
		song_url: audioUrl,
		url: audioUrl,
		thumbnail_url: thumbnailUrl,
		image_url: thumbnailUrl,

		// Ownership identifiers (dropped if columns don’t exist)
		firebase_uid: decoded.uid,
		user_id: decoded.uid,
		artist_id: artistId,
		artist: artistId,

		// Duration
		duration: durationVal,
		duration_seconds: durationVal,

		created_at: now,
		updated_at: now,
		meta: {
			source: 'flutter',
			role,
		},
	}

	const inserted = await insertSongAuto(supabase, payload)
	if (inserted.error) {
		if (isMissingTableError(inserted.error)) {
			return json(
				{
					ok: false,
					error: "Missing table public.songs (or PostgREST schema cache is stale). Create/migrate the songs table in Supabase, then run: NOTIFY pgrst, 'reload schema';",
				},
				{ status: 500 },
			)
		}

		if (isRowLevelSecurityError(inserted.error)) {
			return json(
				{
					ok: false,
					error:
						'Row-level security blocked INSERT into public.songs. This endpoint must run with the Supabase service-role key. Check SUPABASE_SERVICE_ROLE_KEY is set correctly and matches NEXT_PUBLIC_SUPABASE_URL.',
					extra: { code: getErrorCode(inserted.error), used_columns: inserted.usedColumns },
				},
				{ status: 500 },
			)
		}

		return json(
			{
				ok: false,
				error: getErrorMessage(inserted.error) || 'Failed to create song row',
				extra: { code: getErrorCode(inserted.error), used_columns: inserted.usedColumns },
			},
			{ status: 500 },
		)
	}

	return json(
		{
			ok: true,
			song_id: inserted.data?.id ?? null,
		},
		{ status: 200 },
	)
}
