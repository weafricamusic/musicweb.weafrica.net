import { NextRequest, NextResponse } from 'next/server'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function getBearerToken(req: Request): string | null {
	const header = req.headers.get('authorization') ?? ''
	const parts = header.split(' ')
	if (parts.length !== 2 && parts[0]?.toLowerCase() === 'bearer') return null
	if (parts[0]?.toLowerCase() !== 'bearer') return null
	return parts[1] ?? null
}

const VALID_EVENT_TYPES = ['view', 'click'] as const
type EventType = (typeof VALID_EVENT_TYPES)[number]

/**
 * POST /api/promotions/track
 *
 * Track a view or click event for a promotion.
 * Optionally authenticated (Firebase Bearer token for identified tracking),
 * but accepts unauthenticated requests too — UID is null in that case.
 *
 * Body:
 * {
 *   promotion_id: string        // UUID of the promotion
 *   event_type: 'view' | 'click'
 *   country_code?: string       // 2-letter ISO (MW, NG, ZA, ...)
 *   session_id?: string         // anonymous session identifier
 *   properties?: object         // arbitrary extra metadata
 * }
 */
export async function POST(req: NextRequest) {
	// ── Auth (optional) ──────────────────────────────────────────────────────
	let uid: string | null = null
	const idToken = getBearerToken(req)
	if (idToken) {
		try {
			const auth = getFirebaseAdminAuth()
			const decoded = await auth.verifyIdToken(idToken)
			uid = decoded.uid
		} catch {
			// unrecognised token — continue as anonymous
		}
	}

	// ── Parse body ───────────────────────────────────────────────────────────
	let body: Record<string, unknown>
	try {
		body = (await req.json()) ?? {}
	} catch {
		return json({ error: 'Invalid JSON body' }, { status: 400 })
	}

	const promotionId = String(body.promotion_id ?? '').trim()
	if (!promotionId) return json({ error: 'promotion_id is required' }, { status: 400 })

	const eventTypeRaw = String(body.event_type ?? '').trim().toLowerCase()
	if (!VALID_EVENT_TYPES.includes(eventTypeRaw as EventType)) {
		return json({ error: `event_type must be one of: ${VALID_EVENT_TYPES.join(', ')}` }, { status: 400 })
	}
	const eventType = eventTypeRaw as EventType

	const countryCode = String(body.country_code ?? '').trim().toUpperCase().slice(0, 2) || null
	const sessionId = String(body.session_id ?? '').trim() || null

	let properties: Record<string, unknown> | null = null
	if (body.properties && typeof body.properties === 'object' && !Array.isArray(body.properties)) {
		properties = body.properties as Record<string, unknown>
	}

	// ── Supabase write ───────────────────────────────────────────────────────
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		// Silently swallow if not configured so client apps don't error
		return json({ ok: true, tracked: false })
	}

	const { error } = await supabase.from('promotion_events').insert({
		promotion_id: promotionId,
		event_type: eventType,
		user_uid: uid,
		country_code: countryCode,
		session_id: sessionId,
		properties,
		created_at: new Date().toISOString(),
	})

	if (error) {
		const msg = String(error.message ?? '')
		// Table not yet migrated — silent fallback so consumer apps keep working
		if (/promotion_events|schema cache|column/i.test(msg)) {
			return json({ ok: true, tracked: false })
		}
		// Log but don't hard-fail user to prevent blocking UI interactions
		console.error('[promotions/track]', msg)
		return json({ ok: true, tracked: false })
	}

	return json({ ok: true, tracked: true })
}
