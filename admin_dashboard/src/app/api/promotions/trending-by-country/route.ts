import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

const COUNTRY_NAMES: Record<string, string> = {
	MW: 'Malawi',
	NG: 'Nigeria',
	ZA: 'South Africa',
	KE: 'Kenya',
	GH: 'Ghana',
	TZ: 'Tanzania',
	UG: 'Uganda',
	ZW: 'Zimbabwe',
	ZM: 'Zambia',
	ET: 'Ethiopia',
	CM: 'Cameroon',
	SN: 'Senegal',
	CI: "Côte d'Ivoire",
	AO: 'Angola',
	MZ: 'Mozambique',
	RW: 'Rwanda',
	MG: 'Madagascar',
	BJ: 'Benin',
	BF: 'Burkina Faso',
	ML: 'Mali',
	NE: 'Niger',
	SD: 'Sudan',
	SS: 'South Sudan',
	SO: 'Somalia',
	DJ: 'Djibouti',
	ER: 'Eritrea',
	CD: 'DR Congo',
	CG: 'Congo',
	GA: 'Gabon',
	GQ: 'Equatorial Guinea',
	CF: 'Central African Republic',
	TD: 'Chad',
	NA: 'Namibia',
	BW: 'Botswana',
	LS: 'Lesotho',
	SZ: 'Eswatini',
	BI: 'Burundi',
	GN: 'Guinea',
	GW: 'Guinea-Bissau',
	LR: 'Liberia',
	SL: 'Sierra Leone',
	GM: 'Gambia',
	CV: 'Cape Verde',
	ST: 'São Tomé and Príncipe',
	TG: 'Togo',
	MR: 'Mauritania',
	MU: 'Mauritius',
	SC: 'Seychelles',
	KM: 'Comoros',
	MV: 'Maldives',
	EG: 'Egypt',
	LY: 'Libya',
	TN: 'Tunisia',
	DZ: 'Algeria',
	MA: 'Morocco',
}

interface TrendingEntry {
	country_code: string
	country_name: string
	top_artist_id: string | null
	top_artist_name: string | null
	total_plays: number
	rank: number
}

/**
 * GET /api/promotions/trending-by-country
 *
 * Returns a ranked list of countries by song play activity over the last N days.
 * For each country the top artist (by play count) is also returned.
 *
 * Public endpoint — no authentication required.
 *
 * Query params:
 *   days   = integer, default 7  (lookback window)
 *   limit  = integer, default 10 (max countries to return)
 */
export async function GET(req: NextRequest) {
	const { searchParams } = req.nextUrl

	const daysRaw = parseInt(searchParams.get('days') ?? '7', 10)
	const days = Number.isFinite(daysRaw) && daysRaw > 0 ? Math.min(daysRaw, 90) : 7

	const limitRaw = parseInt(searchParams.get('limit') ?? '10', 10)
	const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 50) : 10

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 500 })
	}

	const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString()

	// ── Query 1: play counts per country ─────────────────────────────────────
	interface RawPlayRow {
		country_code: string
		artist_id: string | null
		artist_name: string | null
		play_count: number
	}

	// Pull play events grouped by country_code + artist metadata from analytics_events
	const { data: playRows, error: queryError } = await supabase
		.from('analytics_events')
		.select('country_code, properties')
		.eq('event_name', 'song_play')
		.gte('created_at', since)
		.not('country_code', 'is', null)

	if (queryError) {
		const msg = String(queryError.message ?? '')
		if (/analytics_events|schema cache|column/i.test(msg)) {
			// Analytics table not yet available — return known active countries from promotions
			return await fallbackFromActivePromotions(supabase, limit)
		}
		return json({ error: msg || 'Failed to query trending data' }, { status: 500 })
	}

	// ── Aggregate in-process ─────────────────────────────────────────────────
	// Map: country_code → { artist_id → count }
	type ArtistMap = Map<string, number>
	const countryArtistMap: Map<string, ArtistMap> = new Map()
	const countryPlayCount: Map<string, number> = new Map()

	for (const row of playRows ?? []) {
		const cc = String(row.country_code ?? '').trim().toUpperCase().slice(0, 2)
		if (!cc || cc.length !== 2) continue

		const props =
			row.properties && typeof row.properties === 'object' ? (row.properties as Record<string, unknown>) : {}
		const artistId = String(props.artist_id ?? props.artistId ?? '').trim() || null
		const artistName = String(props.artist_name ?? props.artistName ?? '').trim() || null
		const key = artistId ?? `__anon_${artistName ?? 'unknown'}`

		// Total plays per country
		countryPlayCount.set(cc, (countryPlayCount.get(cc) ?? 0) + 1)

		// Artist breakdown per country
		if (!countryArtistMap.has(cc)) countryArtistMap.set(cc, new Map())
		const artistMap = countryArtistMap.get(cc)!
		artistMap.set(key, (artistMap.get(key) ?? 0) + 1)
	}

	// ── Build sorted result ───────────────────────────────────────────────────
	// We'll also need artist names — store them in a side-map during aggregation
	const artistNames: Map<string, string | null> = new Map()
	for (const row of playRows ?? []) {
		const props =
			row.properties && typeof row.properties === 'object' ? (row.properties as Record<string, unknown>) : {}
		const artistId = String(props.artist_id ?? props.artistId ?? '').trim() || null
		const artistName = String(props.artist_name ?? props.artistName ?? '').trim() || null
		if (artistId) artistNames.set(artistId, artistName)
	}

	const sorted = [...countryPlayCount.entries()]
		.sort((a, b) => b[1] - a[1])
		.slice(0, limit)

	const result: TrendingEntry[] = sorted.map(([cc, totalPlays], idx) => {
		const artistMap = countryArtistMap.get(cc)
		let topArtistId: string | null = null
		let topArtistName: string | null = null

		if (artistMap && artistMap.size > 0) {
			const topEntry = [...artistMap.entries()].sort((a, b) => b[1] - a[1])[0]
			if (topEntry) {
				const [key] = topEntry
				if (!key.startsWith('__anon_')) {
					topArtistId = key
					topArtistName = artistNames.get(key) ?? null
				} else {
					topArtistName = key.replace('__anon_', '') || null
				}
			}
		}

		return {
			country_code: cc,
			country_name: COUNTRY_NAMES[cc] ?? cc,
			top_artist_id: topArtistId,
			top_artist_name: topArtistName,
			total_plays: totalPlays,
			rank: idx + 1,
		}
	})

	// If we have no real data, fall back to active promotions list
	if (result.length === 0) {
		return await fallbackFromActivePromotions(supabase, limit)
	}

	return json({
		ok: true,
		period_days: days,
		updated_at: new Date().toISOString(),
		data: result,
	})
}

/** Fallback: countries with active promotions (no real play data available) */
async function fallbackFromActivePromotions(
	supabase: NonNullable<ReturnType<typeof tryCreateSupabaseAdminClient>>,
	limit: number,
) {
	const { data, error } = await supabase
		.from('promotions')
		.select('country')
		.eq('is_active', true)
		.not('country', 'is', null)
		.limit(100)

	if (error || !data || data.length === 0) {
		// Last resort: return a static list of core WeAfrica markets
		const fallback: TrendingEntry[] = [
			{ country_code: 'MW', country_name: 'Malawi', top_artist_id: null, top_artist_name: null, total_plays: 0, rank: 1 },
			{ country_code: 'NG', country_name: 'Nigeria', top_artist_id: null, top_artist_name: null, total_plays: 0, rank: 2 },
			{ country_code: 'ZA', country_name: 'South Africa', top_artist_id: null, top_artist_name: null, total_plays: 0, rank: 3 },
			{ country_code: 'KE', country_name: 'Kenya', top_artist_id: null, top_artist_name: null, total_plays: 0, rank: 4 },
			{ country_code: 'GH', country_name: 'Ghana', top_artist_id: null, top_artist_name: null, total_plays: 0, rank: 5 },
		].slice(0, limit)

		return NextResponse.json({ ok: true, period_days: 0, updated_at: new Date().toISOString(), data: fallback })
	}

	// Count occurrences per country
	const counts = new Map<string, number>()
	for (const row of data) {
		const cc = String(row.country ?? '').trim().toUpperCase().slice(0, 2)
		if (cc.length === 2) counts.set(cc, (counts.get(cc) ?? 0) + 1)
	}

	const result: TrendingEntry[] = [...counts.entries()]
		.sort((a, b) => b[1] - a[1])
		.slice(0, limit)
		.map(([cc], idx) => ({
			country_code: cc,
			country_name: COUNTRY_NAMES[cc] ?? cc,
			top_artist_id: null,
			top_artist_name: null,
			total_plays: 0,
			rank: idx + 1,
		}))

	return NextResponse.json({
		ok: true,
		period_days: 0,
		updated_at: new Date().toISOString(),
		data: result,
	})
}
