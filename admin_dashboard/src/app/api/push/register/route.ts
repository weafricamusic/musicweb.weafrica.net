import { NextResponse } from 'next/server'
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

type Body = {
	// Preferred field name.
	token?: string
	// Alias to support older/mobile naming.
	fcm_token?: string
	platform?: 'ios' | 'android' | 'web' | 'unknown'
	device_id?: string | null
	country_code?: string | null
	topics?: string[]
	app_version?: string | null
	device_model?: string | null
	locale?: string | null
}

export async function POST(req: Request) {
	const idToken = getBearerToken(req)
	if (!idToken) return json({ error: 'Missing Authorization: Bearer <firebase_id_token>' }, { status: 401 })

	let decoded: { uid: string } | null = null
	try {
		const auth = getFirebaseAdminAuth()
		decoded = (await auth.verifyIdToken(idToken)) as any
	} catch {
		return json({ error: 'Invalid auth token' }, { status: 401 })
	}

	const body = (await req.json().catch(() => null)) as Body | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })

	const token = String(body.token ?? body.fcm_token ?? '').trim()
	if (!token) return json({ error: 'token is required' }, { status: 400 })

	const platformRaw = String(body.platform ?? 'unknown').toLowerCase()
	const platform = platformRaw === 'ios' || platformRaw === 'android' || platformRaw === 'web' ? platformRaw : 'unknown'
	const deviceId = body.device_id == null ? null : String(body.device_id).trim() || null
	const country = body.country_code == null ? null : String(body.country_code).trim().toLowerCase() || null
	const topics = Array.isArray(body.topics) ? body.topics.map((t) => String(t).trim()).filter(Boolean).slice(0, 25) : []
	const appVersion = body.app_version == null ? null : String(body.app_version).trim() || null
	const deviceModel = body.device_model == null ? null : String(body.device_model).trim() || null
	const locale = body.locale == null ? null : String(body.locale).trim() || null

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 500 })

	const payload = {
		token,
		user_uid: decoded!.uid,
		platform,
		device_id: deviceId,
		country_code: country,
		topics,
		app_version: appVersion,
		device_model: deviceModel,
		locale,
		updated_at: new Date().toISOString(),
		last_seen_at: new Date().toISOString(),
	}

	const { error } = await supabase.from('notification_device_tokens').upsert(payload, { onConflict: 'token' })
	if (error) return json({ error: error.message }, { status: 500 })

	return json({ ok: true, message: 'Token registered', user_uid: decoded!.uid })
}
