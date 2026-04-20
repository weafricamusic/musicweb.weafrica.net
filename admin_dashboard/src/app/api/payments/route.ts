import { NextRequest, NextResponse } from 'next/server'
import type { DecodedIdToken } from 'firebase-admin/auth'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

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

function clampInt(raw: string | null, fallback: number, min: number, max: number): number {
	if (!raw) return fallback
	const n = Number(raw)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

/**
 * Consumer payments endpoint.
 *
 * Auth:
 * - `Authorization: Bearer <firebase_id_token>`
 *
 * Currently returns the user's ledger transactions if the finance tables exist.
 */
export async function GET(req: NextRequest) {
	const idToken = getBearerToken(req)
	if (!idToken) return json({ error: 'Missing Authorization: Bearer <firebase_id_token>' }, { status: 401 })

	let decoded: DecodedIdToken
	try {
		const auth = getFirebaseAdminAuth()
		decoded = await auth.verifyIdToken(idToken)
	} catch {
		return json({ error: 'Invalid auth token' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 500 })

	const url = req.nextUrl
	const limit = clampInt(url.searchParams.get('limit'), 100, 1, 500)

	// Best-effort: different deployments may have different transaction schemas.
	const attempts = [
		'id,type,actor_type,actor_id,target_type,target_id,amount_mwk,coins,source,country_code,created_at,meta',
		'id,type,actor_id,amount_mwk,coins,source,created_at',
		'id,type,actor_id,amount_mwk,created_at',
	] as const

	let lastError: unknown = null
	for (const select of attempts) {
		const { data, error } = await supabase
			.from('transactions')
			.select(select)
			.eq('actor_id', decoded.uid)
			.order('created_at', { ascending: false })
			.limit(limit)

		if (!error) {
			return NextResponse.json(
				{ ok: true, user: { uid: decoded.uid }, transactions: data ?? [] },
				{ headers: { 'cache-control': 'no-store' } },
			)
		}

		const msg = String((error as any)?.message ?? '')
		const missing = /schema cache|could not find|does not exist|PGRST205/i.test(msg)
		if (missing) {
			return NextResponse.json(
				{ ok: true, user: { uid: decoded.uid }, transactions: [], warning: 'transactions table not found (apply finance migration).' },
				{ headers: { 'cache-control': 'no-store' } },
			)
		}

		lastError = error
	}

	return json({ error: (lastError as any)?.message ?? 'Query failed' }, { status: 500 })
}
