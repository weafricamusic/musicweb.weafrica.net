import { NextRequest, NextResponse } from 'next/server'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import {
	isPaidPromotionStatus,
	normalizeCountryCode,
	promotionTypeFromContentType,
	toPositiveInt,
} from '@/lib/admin/promotions'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function getBearerToken(req: Request): string | null {
	const header = req.headers.get('authorization') ?? ''
	const parts = header.split(' ')
	if (parts.length !== 2 || parts[0]?.toLowerCase() !== 'bearer') return null
	return parts[1] ?? null
}

const VALID_COIN_TIERS = [
	{ coins: 200, duration_days: 1 },
	{ coins: 500, duration_days: 3 },
	{ coins: 1000, duration_days: 7 },
]

const VALID_SURFACES = ['home_banner', 'discover', 'feed', 'live_battle', 'events']
const VALID_CONTENT_TYPES = ['song', 'video', 'dj_profile', 'battle', 'artist', 'dj']

/**
 * POST /api/promotions/paid
 *
 * Artist or DJ submits a paid promotion request.
 * Requires Firebase Bearer token.
 * Coins are reserved; admin must approve before the promotion goes live.
 *
 * Body:
 * {
 *   content_id: string        // song/video/DJ/battle ID
 *   content_type: string      // song | video | dj_profile | battle | artist | dj
 *   title?: string            // optional display title
 *   country: string           // 2-letter ISO (MW, NG, ZA, ...)
 *   coins: number             // 200 | 500 | 1000
 *   duration_days?: number    // inferred from coins if omitted
 *   audience?: string         // all | fans | age_18_plus (informational)
 *   surface?: string          // home_banner | discover | feed | live_battle | events
 * }
 */
export async function POST(req: NextRequest) {
	// ── Auth ─────────────────────────────────────────────────────────────────
	const idToken = getBearerToken(req)
	if (!idToken) {
		return json({ error: 'Missing Authorization: Bearer <firebase_id_token>' }, { status: 401 })
	}

	let uid: string
	try {
		const auth = getFirebaseAdminAuth()
		const decoded = await auth.verifyIdToken(idToken)
		uid = decoded.uid
	} catch {
		return json({ error: 'Invalid or expired auth token' }, { status: 401 })
	}

	// ── Parse body ───────────────────────────────────────────────────────────
	let body: Record<string, unknown>
	try {
		body = (await req.json()) ?? {}
	} catch {
		return json({ error: 'Invalid JSON body' }, { status: 400 })
	}

	const contentId = String(body.content_id ?? '').trim()
	if (!contentId) return json({ error: 'content_id is required' }, { status: 400 })

	const contentTypeRaw = String(body.content_type ?? 'song').trim().toLowerCase()
	if (!VALID_CONTENT_TYPES.includes(contentTypeRaw)) {
		return json(
			{ error: `content_type must be one of: ${VALID_CONTENT_TYPES.join(', ')}` },
			{ status: 400 },
		)
	}

	const countryRaw = String(body.country ?? 'MW').trim()
	const country = normalizeCountryCode(countryRaw)

	const coinsRaw = toPositiveInt(body.coins)
	if (!coinsRaw) return json({ error: 'coins must be a positive integer (200, 500, or 1000)' }, { status: 400 })

	// Enforce only valid coin tiers
	const tier = VALID_COIN_TIERS.find((t) => t.coins === coinsRaw)
	if (!tier) {
		return json(
			{ error: `coins must be one of: ${VALID_COIN_TIERS.map((t) => t.coins).join(', ')}` },
			{ status: 400 },
		)
	}

	const durationDays = toPositiveInt(body.duration_days) ?? tier.duration_days

	const surfaceRaw = String(body.surface ?? '').trim().toLowerCase()
	const surface = VALID_SURFACES.includes(surfaceRaw) ? surfaceRaw : null

	const title = String(body.title ?? '').trim() || null
	const audience = String(body.audience ?? 'all').trim() || 'all'
	const promotionType = promotionTypeFromContentType(contentTypeRaw)

	// ── Supabase write ───────────────────────────────────────────────────────
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 500 })
	}

	const nowIso = new Date().toISOString()

	const { data, error } = await supabase
		.from('paid_promotions')
		.insert({
			user_id: uid,
			content_id: contentId,
			content_type: contentTypeRaw,
			promotion_type: promotionType,
			title,
			country,
			coins: coinsRaw,
			duration_days: durationDays,
			audience,
			surface,
			status: 'pending',
			created_at: nowIso,
			updated_at: nowIso,
		})
		.select('id,status,coins,duration_days,country')
		.single()

	if (error) {
		const msg = String(error.message ?? '')
		if (/paid_promotions|column|schema cache/i.test(msg)) {
			return json(
				{ error: 'Paid promotions table not configured yet. Contact the platform admin.' },
				{ status: 503 },
			)
		}
		return json({ error: msg || 'Failed to submit paid promotion' }, { status: 500 })
	}

	return json(
		{
			ok: true,
			data,
			message:
				'Paid promotion submitted successfully. It is now pending review by the admin. You will be notified when it is approved.',
		},
		{ status: 201 },
	)
}

/**
 * GET /api/promotions/paid
 *
 * Creator can fetch their own paid promotion history.
 * Requires Firebase Bearer token.
 */
export async function GET(req: NextRequest) {
	const idToken = getBearerToken(req)
	if (!idToken) return json({ error: 'Missing Authorization header' }, { status: 401 })

	let uid: string
	try {
		const auth = getFirebaseAdminAuth()
		const decoded = await auth.verifyIdToken(idToken)
		uid = decoded.uid
	} catch {
		return json({ error: 'Invalid auth token' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'Server not configured' }, { status: 500 })

	const { data, error } = await supabase
		.from('paid_promotions')
		.select('id,content_id,content_type,title,country,coins,duration_days,audience,surface,status,created_at')
		.eq('user_id', uid)
		.order('created_at', { ascending: false })
		.limit(50)

	if (error) return json({ error: String(error.message ?? 'query failed') }, { status: 500 })

	return json({ ok: true, data: data ?? [] })
}
