import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type ArtistRow = {
	id: string
	stage_name?: string | null
	name?: string | null
	display_name?: string | null
	verified?: boolean | null
	approved?: boolean | null
	status?: string | null
	blocked?: boolean | null
	created_at?: string | null
	songs_count?: number | null
	videos_count?: number | null
}

type Suggestion = {
	artist_id: string
	label: string
	reason: string
	priority: number
	country_code: string | null
}

type Candidate = {
	a: ArtistRow
	score: number
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function clampInt(v: string | null, def: number, min: number, max: number): number {
	const n = v ? Number(v) : def
	if (!Number.isFinite(n)) return def
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

function normalizeCountry(code: string | null): string | null {
	const c = (code ?? '').trim().toUpperCase()
	if (!c) return null
	if (!/^[A-Z]{2}$/.test(c)) return null
	return c
}

function toLabel(a: ArtistRow): string {
	return String(a.stage_name || a.display_name || a.name || a.id)
}

function truthy(v: unknown): boolean {
	return v === true || v === 1 || v === 'true'
}

function computeScore(a: ArtistRow): number {
	// Keep it schema-flexible: if counts exist we use them, otherwise rely on verification + recency.
	const verified = truthy(a.verified)
	const approved = truthy(a.approved)
	const blocked = truthy(a.blocked)
	if (blocked) return -999

	const songs = Number.isFinite(Number(a.songs_count)) ? Number(a.songs_count) : 0
	const videos = Number.isFinite(Number(a.videos_count)) ? Number(a.videos_count) : 0
	const content = songs + videos

	const createdMs = a.created_at ? Date.parse(String(a.created_at)) : 0
	const ageDays = createdMs ? (Date.now() - createdMs) / (1000 * 60 * 60 * 24) : 999
	const recency = ageDays <= 0 ? 1 : 1 / Math.sqrt(Math.max(1, ageDays))

	let score = 0
	if (verified) score += 2
	if (approved) score += 0.5
	if (String(a.status ?? '').toLowerCase() === 'active') score += 0.25

	// Content helps but shouldn’t dominate.
	score += Math.min(2, Math.log10(1 + content))
	// Recent sign-ups get a gentle boost.
	score += 1.5 * recency

	return score
}

function pickProvider(raw: string | null): 'heuristic' | 'huggingface' {
	const v = (raw ?? '').trim().toLowerCase()
	if (v === 'ai' || v === 'hf' || v === 'huggingface') return 'huggingface'
	return 'heuristic'
}

function safeJsonExtract(text: string): any | null {
	const s = String(text ?? '')
	const start = s.indexOf('{')
	const end = s.lastIndexOf('}')
	if (start < 0 || end <= start) return null
	const slice = s.slice(start, end + 1)
	try {
		return JSON.parse(slice)
	} catch {
		return null
	}
}

async function hfRerank(options: {
	token: string
	model: string
	limit: number
	countryCode: string | null
	candidates: Candidate[]
}): Promise<{ rankedIds: string[]; note?: string } | null> {
	const { token, model, limit, countryCode, candidates } = options
	if (!token || !model) return null
	if (!candidates.length) return null

	const maxCandidates = Math.min(80, Math.max(limit * 6, 30))
	const trimmed = candidates.slice(0, maxCandidates)

	const payloadCandidates = trimmed.map(({ a, score }) => ({
		id: String(a.id),
		label: toLabel(a),
		verified: truthy(a.verified),
		approved: truthy(a.approved),
		status: String(a.status ?? ''),
		blocked: truthy(a.blocked),
		created_at: a.created_at ?? null,
		songs_count: Number.isFinite(Number(a.songs_count)) ? Number(a.songs_count) : null,
		videos_count: Number.isFinite(Number(a.videos_count)) ? Number(a.videos_count) : null,
		heuristic_score: Math.round(score * 1000) / 1000,
	}))

	const prompt = [
		'You are helping an admin curate Featured Artists for a music app.',
		'Rank the candidates to maximize quality and discovery. Prefer verified/approved/active, strong content, and avoid blocked.',
		countryCode ? `Target country: ${countryCode}. Prefer artists relevant to that country when possible.` : 'No country filter requested.',
		`Return STRICT JSON only, with this shape: {"ranked_artist_ids": ["id1", ...]}.`,
		`Pick at most ${limit} unique IDs from the candidate list. Do not invent IDs.`,
		'Candidates JSON:',
		JSON.stringify(payloadCandidates),
	].join('\n')

	const url = `https://api-inference.huggingface.co/models/${encodeURIComponent(model)}`
	const res = await fetch(url, {
		method: 'POST',
		headers: {
			accept: 'application/json',
			'content-type': 'application/json',
			authorization: `Bearer ${token}`,
		},
		body: JSON.stringify({
			inputs: prompt,
			parameters: {
				max_new_tokens: 256,
				return_full_text: false,
				temperature: 0.2,
			},
		}),
	})

	const raw = await res.text()
	if (!res.ok) return null

	let generated = ''
	try {
		const parsed = JSON.parse(raw) as any
		if (Array.isArray(parsed) && parsed[0] && typeof parsed[0].generated_text === 'string') {
			generated = parsed[0].generated_text
		} else if (parsed && typeof parsed.generated_text === 'string') {
			generated = parsed.generated_text
		} else if (typeof raw === 'string') {
			generated = raw
		}
	} catch {
		generated = raw
	}

	const obj = safeJsonExtract(generated)
	const idsRaw = Array.isArray(obj?.ranked_artist_ids) ? obj.ranked_artist_ids : null
	if (!idsRaw) return null

	const allowed = new Set(trimmed.map((c) => String(c.a.id)))
	const rankedIds = (idsRaw as any[])
		.map((x) => (typeof x === 'string' ? x : String(x ?? '')).trim())
		.filter((x) => x && allowed.has(x))
		.filter((x, idx, arr) => arr.indexOf(x) === idx)
		.slice(0, limit)

	if (!rankedIds.length) return null
	return { rankedIds, note: 'AI reranked (Hugging Face)' }
}

function buildReason(a: ArtistRow): string {
	const parts: string[] = []
	if (truthy(a.verified)) parts.push('verified')
	if (truthy(a.approved)) parts.push('approved')
	if (String(a.status ?? '').toLowerCase() === 'active') parts.push('active')
	const songs = Number.isFinite(Number(a.songs_count)) ? Number(a.songs_count) : null
	const videos = Number.isFinite(Number(a.videos_count)) ? Number(a.videos_count) : null
	if (songs !== null || videos !== null) parts.push(`content: ${(songs ?? 0) + (videos ?? 0)}`)
	if (a.created_at) parts.push('recent')
	return parts.length ? parts.join(' · ') : 'auto-ranked'
}

async function loadFeaturedArtistIds(supabase: ReturnType<typeof tryCreateSupabaseAdminClient>) {
	try {
		const { data, error } = await (supabase as any)
			.from('featured_artists')
			.select('artist_id')
			.limit(1000)
		if (error) return new Set<string>()
		const ids = (data ?? []).map((r: any) => String(r.artist_id ?? '')).filter(Boolean)
		return new Set(ids)
	} catch {
		return new Set<string>()
	}
}

async function loadArtists(supabase: ReturnType<typeof tryCreateSupabaseAdminClient>, limit: number): Promise<ArtistRow[]> {
	const trySelect = async (columns: string) => {
		const { data, error } = await (supabase as any)
			.from('artists')
			.select(columns)
			.order('created_at', { ascending: false })
			.limit(limit)
		if (error) throw error
		return (data ?? []) as ArtistRow[]
	}

	// Try richer schema first; fall back if some columns don’t exist.
	try {
		return await trySelect('id,stage_name,name,display_name,verified,approved,status,blocked,created_at,songs_count,videos_count')
	} catch {
		try {
			return await trySelect('id,stage_name,name,display_name,verified,approved,status,blocked,created_at')
		} catch {
			return await trySelect('id,stage_name,name,display_name,created_at')
		}
	}
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })

	const canManage =
		ctx.admin.role === 'super_admin' ||
		ctx.admin.role === 'operations_admin' ||
		ctx.permissions.can_manage_artists
	if (!canManage) return json({ error: 'Forbidden' }, { status: 403 })

	const url = new URL(req.url)
	const limit = clampInt(url.searchParams.get('limit'), 10, 1, 50)
	const countryCode = normalizeCountry(url.searchParams.get('country_code'))
	const providerRequested = pickProvider(url.searchParams.get('provider'))

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const [featuredIds, artists] = await Promise.all([
		loadFeaturedArtistIds(supabase),
		loadArtists(supabase, 250),
	])

	const candidates: Candidate[] = artists
		.filter((a) => a && a.id && !featuredIds.has(String(a.id)))
		.filter((a) => !truthy(a.blocked))
		.map((a) => ({ a, score: computeScore(a) }))
		.sort((x, y) => y.score - x.score)
		.slice(0, Math.min(120, Math.max(limit * 8, 40)))

	let ranked: Candidate[] = candidates
	let providerUsed: 'free-heuristic' | 'huggingface' = 'free-heuristic'
	let warning: string | undefined

	if (providerRequested === 'huggingface') {
		const token = (process.env.HUGGINGFACE_API_KEY || process.env.HF_API_TOKEN || '').trim()
		const model = (process.env.HUGGINGFACE_FEATURED_ARTISTS_MODEL || process.env.HUGGINGFACE_MODEL || '').trim()
		if (!token) {
			warning = 'HUGGINGFACE_API_KEY not set; falling back to heuristic.'
		} else if (!model) {
			warning = 'HUGGINGFACE_FEATURED_ARTISTS_MODEL not set; falling back to heuristic.'
		} else {
			try {
				const ai = await hfRerank({ token, model, limit, countryCode, candidates })
				if (ai?.rankedIds?.length) {
					const byId = new Map(candidates.map((c) => [String(c.a.id), c]))
					ranked = ai.rankedIds.map((id) => byId.get(id)).filter(Boolean) as Candidate[]
					providerUsed = 'huggingface'
				} else {
					warning = 'AI rerank failed; falling back to heuristic.'
				}
			} catch {
				warning = 'AI request error; falling back to heuristic.'
			}
		}
	}

	if (providerUsed === 'free-heuristic') ranked = ranked.slice(0, limit)

	const suggestions: Suggestion[] = ranked.map(({ a }, idx) => {
		// Priority suggestion: higher for top-ranked; still editable.
		const priority = Math.max(0, (limit - idx) * 10)
		return {
			artist_id: String(a.id),
			label: toLabel(a),
			reason: providerUsed === 'huggingface' ? `${buildReason(a)} · AI reranked` : buildReason(a),
			priority,
			country_code: countryCode,
		}
	})

	return json(
		{ ok: true, provider: providerUsed, warning, suggestions },
		{ headers: { 'cache-control': 'no-store' } },
	)
}
