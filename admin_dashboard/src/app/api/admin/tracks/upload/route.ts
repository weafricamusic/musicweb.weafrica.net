import { NextResponse } from 'next/server'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'

import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { compressMediaBestEffort } from '@/lib/media/transcode'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function asBool(value: unknown, fallback: boolean): boolean {
	if (typeof value === 'boolean') return value
	if (typeof value !== 'string') return fallback
	const v = value.trim().toLowerCase()
	if (v === '1' || v === 'true' || v === 'yes' || v === 'on') return true
	if (v === '0' || v === 'false' || v === 'no' || v === 'off') return false
	return fallback
}

function normalizeText(value: unknown, maxLen: number): string | null {
	const s = String(value ?? '').trim()
	if (!s) return null
	if (s.length > maxLen) return s.slice(0, maxLen)
	return s
}

function normalizeUuid(value: unknown): string | null {
	const s = String(value ?? '').trim()
	if (!s) return null
	return looksLikeUuid(s) ? s : null
}

function getFileExt(name: string, mime: string): string {
	const lower = String(name ?? '').trim().toLowerCase()
	const dot = lower.lastIndexOf('.')
	const ext = dot >= 0 ? lower.slice(dot + 1) : ''
	const allowed = new Set(['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'])
	if (ext && allowed.has(ext)) return ext

	const m = String(mime ?? '').toLowerCase()
	if (m.includes('mpeg')) return 'mp3'
	if (m.includes('wav')) return 'wav'
	if (m.includes('aac')) return 'aac'
	if (m.includes('ogg')) return 'ogg'
	if (m.includes('mp4') || m.includes('m4a')) return 'm4a'
	if (m.includes('flac')) return 'flac'
	return 'mp3'
}

function findMissingColumn(message: string | undefined): string | null {
	const msg = String(message ?? '')
	// Postgres error style
	let m = msg.match(/column \"([^\"]+)\" of relation/i)
	if (m?.[1]) return m[1]
	// Postgres insert/update style
	m = msg.match(/column \"([^\"]+)\" does not exist/i)
	if (m?.[1]) return m[1]
	// PostgREST schema cache style
	m = msg.match(/could not find the '([^']+)' column/i)
	if (m?.[1]) return m[1]
	// PostgREST sometimes qualifies with the table name: `column songs.name does not exist`
	m = msg.match(/column (?:[a-z0-9_]+\.)?([a-z0-9_]+) does not exist/i)
	if (m?.[1]) return m[1]
	m = msg.match(/column ([a-z0-9_]+) does not exist/i)
	if (m?.[1]) return m[1]
	return null
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

function looksLikeUuid(value: string | null | undefined): boolean {
	if (!value) return false
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
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
	// Postgres: insufficient_privilege is 42501, commonly returned for RLS insert/update blocks.
	return code === '42501' || message.includes('row-level security')
}

async function detectExistingColumns(args: {
	supabase: SupabaseClient
	table: string
	columns: string[]
}): Promise<{ columns: string[]; error: string | null }> {
	let cols = [...new Set(args.columns)].filter(Boolean)
	// If the table doesn't exist, detect that explicitly.
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

	const tryInsert = async () =>
		await supabase.from('songs').insert(current).select('id').single<{ id: string | number }>()

	let res = await tryInsert()
	if (!res.error) return { data: res.data ?? null, error: null, usedColumns }

	// If types don't match for tags/categories, retry with safer encodings.
	const msg = getErrorMessage(res.error)
	const hasTags = Object.prototype.hasOwnProperty.call(current, 'tags')
	const hasCategories = Object.prototype.hasOwnProperty.call(current, 'categories')
	if ((hasTags || hasCategories) && /invalid input syntax|cannot cast|malformed array literal|expects json/i.test(msg.toLowerCase())) {
		if (hasTags) {
			const v = current.tags
			if (Array.isArray(v)) current.tags = v.join(', ')
		}
		if (hasCategories) {
			const v = current.categories
			if (Array.isArray(v)) current.categories = v.join(', ')
		}
		res = await tryInsert()
		if (!res.error) return { data: res.data ?? null, error: null, usedColumns }
	}

	return { data: null, error: res.error, usedColumns }
}

function readId(value: unknown): string | number | null {
	if (!value || typeof value !== 'object') return null
	const v = value as { id?: unknown }
	if (typeof v.id === 'string' && v.id.trim()) return v.id
	if (typeof v.id === 'number' && Number.isFinite(v.id)) return v.id
	return null
}

export async function POST(req: Request) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		// Best-fit permission for content creation in the current RBAC schema.
		assertPermission(adminCtx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin uploads.' },
			{ status: 500 },
		)
	}

	const form = await req.formData().catch(() => null)
	if (!form) return json({ error: 'Invalid multipart form' }, { status: 400 })

	const title = normalizeText(form.get('title'), 120)
	const artistId = normalizeText(form.get('artist_id'), 80)
	const albumId = normalizeUuid(form.get('album_id') ?? form.get('albumId'))
	const artistName = normalizeText(form.get('artist_name'), 120)
	const genre = normalizeText(form.get('genre'), 64)
	const mood = normalizeText(form.get('mood'), 64)
	const tagsRaw = normalizeText(form.get('tags'), 240)
	// Default to approved so creator/admin uploads appear in consumer feeds.
	// (Can be unchecked to force moderation/pending content.)
	const approved = asBool(form.get('approved'), true)
	const isActive = asBool(form.get('is_active'), true)

	const audio = form.get('audio')
	if (!title) return json({ error: 'Missing title' }, { status: 400 })
	if (!artistId) return json({ error: 'Missing artist_id' }, { status: 400 })
	if (!(audio instanceof File)) return json({ error: 'Missing audio file' }, { status: 400 })

	// Keep this modest; if you need very large uploads, switch to signed upload URLs.
	const maxBytes = 50 * 1024 * 1024
	if (audio.size > maxBytes) {
		return json({ error: `File too large (max ${maxBytes} bytes)` }, { status: 413 })
	}

	const bucket = (process.env.SUPABASE_SONGS_BUCKET ?? '').trim() || 'songs'
	const compress = asBool(form.get('compress'), true)

	// Resolve artist ownership identifiers (different schemas use different foreign keys).
	let artist: { firebase_uid: string | null; user_id: string | null } | null = null
	try {
		const { data } = await supabase
			.from('artists')
			.select('id,firebase_uid,user_id')
			.eq('id', artistId)
			.maybeSingle<{ id: string; firebase_uid: string | null; user_id: string | null }>()
		artist = data ? { firebase_uid: data.firebase_uid ?? null, user_id: data.user_id ?? null } : null
	} catch {
		artist = null
	}

	const inferredUserId =
		artist?.user_id ??
		(looksLikeUuid(artist?.firebase_uid) ? artist?.firebase_uid ?? null : null) ??
		(looksLikeUuid(artistId) ? artistId : null) ??
		artist?.firebase_uid ??
		artistId

	// Best-effort: validate album_id when provided.
	if (albumId) {
		try {
			const { data, error } = await supabase.from('albums').select('id').eq('id', albumId).limit(1).maybeSingle<any>()
			if (error) {
				const msg = String(error.message ?? '')
				const missing = /schema cache|could not find the table|does not exist|PGRST205/i.test(msg)
				if (missing) {
					return json(
						{ error: "albums table not found. Apply the albums migration, then run: NOTIFY pgrst, 'reload schema';" },
						{ status: 500 },
					)
				}
				return json({ error: `Failed to validate album_id: ${error.message}` }, { status: 500 })
			}
			if (!data) return json({ error: 'Invalid album_id (album not found)' }, { status: 400 })
		} catch {
			// If validation fails unexpectedly, treat as server error (don’t silently mis-link).
			return json({ error: 'Failed to validate album_id' }, { status: 500 })
		}
	}

	let bytes: Buffer
	try {
		bytes = Buffer.from(await audio.arrayBuffer())
	} catch {
		return json({ error: 'Failed to read upload' }, { status: 400 })
	}

	let contentType = audio.type || 'audio/mpeg'
	let ext = getFileExt(audio.name, contentType)
	if (compress) {
		const compressed = await compressMediaBestEffort({ bytes, contentType, filename: audio.name })
		bytes = compressed.bytes
		contentType = compressed.contentType
		if (compressed.ext) ext = compressed.ext
	}

	const objectPath = `tracks/${encodeURIComponent(artistId)}/${Date.now()}-${randomUUID()}.${ext}`

	const uploadRes = await supabase.storage
		.from(bucket)
		.upload(objectPath, bytes, { contentType, upsert: false })

	if (uploadRes.error) {
		return json(
			{ error: `Storage upload failed: ${uploadRes.error.message}` },
			{ status: 500 },
		)
	}

	const publicUrl = supabase.storage.from(bucket).getPublicUrl(objectPath)?.data?.publicUrl ?? null
	let signedPreviewUrl: string | null = null
	try {
		const { data } = await supabase.storage.from(bucket).createSignedUrl(objectPath, 60 * 60)
		signedPreviewUrl = data?.signedUrl ?? null
	} catch {
		signedPreviewUrl = null
	}

	const tags = tagsRaw
		? tagsRaw
			.split(',')
			.map((t) => t.trim())
			.filter((t) => t.length > 0)
			.slice(0, 25)
		: []

	const nowIso = new Date().toISOString()
	const isPublic = approved && isActive

	const payload: Record<string, unknown> = {
		title,
		name: title,
		song_title: title,
		song_name: title,
		track_title: title,
		track_name: title,
		artist_id: artistId,
		artist: artistId,
		album_id: albumId,
		firebase_uid: artist?.firebase_uid ?? null,
		user_id: inferredUserId,

		// Optional display name provided by admin.
		artist_name: artistName,
		stage_name: artistName,
		creator_name: artistName,
		owner_name: artistName,

		// Categorization (best-effort; dropped if columns don't exist).
		genre,
		primary_genre: genre,
		category: genre,
		mood,
		// Prefer array, but insert may retry as string if schema expects text.
		tags: tags.length ? tags : null,
		categories: tags.length ? tags : null,
		approved,
		is_active: isActive,
		is_public: isPublic,
		visibility: isPublic ? 'public' : 'private',
		is_published: isPublic,
		published_at: isPublic ? nowIso : null,
		status: isActive ? 'active' : 'inactive',

		// Best-effort storage fields; schema fallback will drop unknown columns.
		audio_bucket: bucket,
		audio_path: objectPath,
		audio_url: publicUrl,
		audio: publicUrl,
		storage_bucket: bucket,
		storage_path: objectPath,
		storage_url: publicUrl,
		file_bucket: bucket,
		file_path: objectPath,
		file_url: publicUrl,
		file: publicUrl,
		song_url: publicUrl,
		url: publicUrl,
		created_at: nowIso,
		updated_at: nowIso,

		// Lightweight audit trail.
		meta: {
			uploader: 'admin_dashboard',
			uploaded_by: adminCtx.admin.email,
			album_id: albumId,
			artist_name: artistName,
			genre,
			mood,
			tags,
			original_name: audio.name,
			content_type: audio.type,
			stored_content_type: contentType,
			compressed: compress,
		},
	}

	const inserted = await insertSongAuto(supabase, payload)
	if (inserted.error) {
		// Best-effort cleanup if DB insert fails.
		try {
			await supabase.storage.from(bucket).remove([objectPath])
		} catch {
			// ignore
		}

		if (isMissingTableError(inserted.error)) {
			return json(
				{
					error:
						"Missing table public.songs (or PostgREST schema cache is stale). Create/migrate the songs table in Supabase, then run: NOTIFY pgrst, 'reload schema';",
				},
				{ status: 500 },
			)
		}

		if (isRowLevelSecurityError(inserted.error)) {
			return json(
				{
					error:
						'Row-level security blocked INSERT into public.songs. This admin endpoint must use the Supabase service-role key. Check SUPABASE_SERVICE_ROLE_KEY is set to the service_role JWT (and matches NEXT_PUBLIC_SUPABASE_URL). You can verify server env via /api/admin/supabase-env-debug.',
					extra: {
						code: getErrorCode(inserted.error),
						used_columns: inserted.usedColumns,
					},
				},
				{ status: 500 },
			)
		}

		return json(
			{
				error: getErrorMessage(inserted.error) || 'Failed to create song row',
				extra: {
					code: getErrorCode(inserted.error),
					used_columns: inserted.usedColumns,
				},
			},
			{ status: 500 },
		)
	}

	return json(
		{
			ok: true,
			song_id: readId(inserted.data),
			bucket,
			path: objectPath,
			public_url: publicUrl,
			signed_preview_url: signedPreviewUrl,
		},
		{ status: 200 },
	)
}
