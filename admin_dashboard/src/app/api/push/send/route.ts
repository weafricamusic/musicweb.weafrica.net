import { NextResponse } from 'next/server'
import { getFirebaseAdminMessaging } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { randomUUID } from 'node:crypto'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function getInternalSecret(req: Request): string | null {
	const raw = req.headers.get('authorization') || req.headers.get('Authorization')
	if (raw) {
		const m = raw.match(/^Bearer\s+(.+)$/i)
		if (m) return m[1]!.trim()
	}
	return (req.headers.get('x-push-internal-secret') || '').trim() || null
}

type Body = {
	notification: { title?: string | null; body: string }
	data?: Record<string, unknown>

	// Used for token-mode targeting + rate limiting dimensions (e.g. trending).
	token_topic?: string | null

	audience:
		| { type: 'user_uid'; uid: string }
		| { type: 'user_uids'; uids: string[] }
		| { type: 'filters'; country_code?: string | null; role?: 'consumers' | 'artists' | 'djs' | null }

	// Optional safety / spam control.
	max_per_user_per_day?: number | null
	limit_tokens?: number | null
}

function asStringData(input: Record<string, unknown> | undefined): Record<string, string> {
	const out: Record<string, string> = {}
	if (!input || typeof input !== 'object') return out
	for (const [k, v] of Object.entries(input)) {
		if (v == null) continue
		out[String(k)] = typeof v === 'string' ? v : JSON.stringify(v)
	}
	return out
}

function todayUtcDateString(): string {
	const now = new Date()
	const y = now.getUTCFullYear()
	const m = String(now.getUTCMonth() + 1).padStart(2, '0')
	const d = String(now.getUTCDate()).padStart(2, '0')
	return `${y}-${m}-${d}`
}

function parseOptionalPositiveInt(value: unknown): number | null {
	if (value == null) return null
	const n = typeof value === 'number' ? value : Number(String(value))
	if (!Number.isFinite(n)) return null
	const i = Math.floor(n)
	return i > 0 ? i : null
}

function ensureNotificationId(data: Record<string, unknown> | undefined): { data: Record<string, unknown>; notificationId: string } {
	const base: Record<string, unknown> = data && typeof data === 'object' ? data : {}
	const existing = (base as any).notification_id
	if (existing != null && String(existing).trim()) return { data: base, notificationId: String(existing).trim() }
	const notificationId = randomUUID()
	return { data: { ...base, notification_id: notificationId }, notificationId }
}

export async function POST(req: Request) {
	const expected = (process.env.PUSH_INTERNAL_SECRET || '').trim()
	if (!expected) return json({ error: 'Server not configured (missing PUSH_INTERNAL_SECRET).' }, { status: 503 })

	const provided = getInternalSecret(req)
	if (!provided || provided !== expected) return json({ error: 'Unauthorized' }, { status: 401 })

	const body = (await req.json().catch(() => null)) as Body | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })

	const messageBody = String(body.notification?.body ?? '').trim()
	if (!messageBody) return json({ error: 'notification.body is required' }, { status: 400 })

	const titleRaw = body.notification?.title
	const title = titleRaw == null ? undefined : String(titleRaw).trim() || undefined

	const tokenTopicRaw = body.token_topic
	const tokenTopic = tokenTopicRaw == null ? null : String(tokenTopicRaw).trim() || null

	const maxPerUserPerDay = parseOptionalPositiveInt(body.max_per_user_per_day)
	const limitTokens = Math.max(1, Math.min(5000, parseOptionalPositiveInt(body.limit_tokens) ?? 5000))

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'Server not configured (missing SUPABASE_SERVICE_ROLE_KEY).' }, { status: 503 })

	let q = supabase
		.from('notification_device_tokens')
		.select('token,user_uid,last_seen_at,topics,country_code')
		.order('last_seen_at', { ascending: false })
		.limit(limitTokens)

	if (body.audience?.type === 'user_uid') {
		const uid = String(body.audience.uid ?? '').trim()
		if (!uid) return json({ error: 'audience.uid is required' }, { status: 400 })
		q = q.eq('user_uid', uid)
	} else if (body.audience?.type === 'user_uids') {
		const uids = Array.isArray(body.audience.uids) ? body.audience.uids.map((u) => String(u).trim()).filter(Boolean) : []
		if (!uids.length) return json({ error: 'audience.uids is required' }, { status: 400 })
		q = q.in('user_uid', uids)
	} else if (body.audience?.type === 'filters') {
		const country = body.audience.country_code == null ? null : String(body.audience.country_code).trim().toLowerCase() || null
		const role = body.audience.role == null ? null : body.audience.role
		if (country) q = q.eq('country_code', country)
		if (role) q = q.contains('topics', [role])
	} else {
		return json({ error: 'audience is required' }, { status: 400 })
	}

	if (tokenTopic && tokenTopic !== 'all') {
		q = q.contains('topics', [tokenTopic])
	}

	const { data: rows, error } = await q
	if (error) return json({ error: error.message }, { status: 500 })

	const candidates = (rows ?? []).map((r: any) => ({ token: String(r?.token ?? '').trim(), user_uid: r?.user_uid ? String(r.user_uid).trim() : null }))
	const tokens = candidates.map((c) => c.token).filter(Boolean)
	if (!tokens.length) return json({ error: 'No registered device tokens found.' }, { status: 400 })

	let allowedTokens = tokens
	let allowedUserUids: string[] = []

	if (maxPerUserPerDay != null) {
		if (!tokenTopic) return json({ error: 'token_topic is required when using max_per_user_per_day' }, { status: 400 })

		const day = todayUtcDateString()
		const distinctUids = Array.from(new Set(candidates.map((c) => c.user_uid).filter(Boolean))) as string[]
		if (!distinctUids.length) return json({ error: 'No user_uids found for device tokens.' }, { status: 400 })

		const { data: logRows, error: logError } = await supabase
			.from('notification_push_send_log')
			.select('user_uid,token_topic,day')
			.eq('token_topic', tokenTopic)
			.eq('day', day)
			.in('user_uid', distinctUids)
		if (logError) return json({ error: logError.message }, { status: 500 })

		const counts = new Map<string, number>()
		for (const r of logRows ?? []) {
			const uid = String((r as any).user_uid ?? '').trim()
			if (!uid) continue
			counts.set(uid, (counts.get(uid) ?? 0) + 1)
		}

		allowedUserUids = distinctUids.filter((uid) => (counts.get(uid) ?? 0) < maxPerUserPerDay)
		const allowedSet = new Set(allowedUserUids)
		allowedTokens = candidates.filter((c) => c.user_uid && allowedSet.has(c.user_uid)).map((c) => c.token)
		if (!allowedTokens.length) return json({ error: 'Rate limit: no eligible users left to receive this push.' }, { status: 429 })
	} else {
		allowedUserUids = Array.from(new Set(candidates.map((c) => c.user_uid).filter(Boolean))) as string[]
	}

	const messaging = getFirebaseAdminMessaging()
	const ensured = ensureNotificationId(body.data)
	const data = asStringData(ensured.data)

	// Multicast limit is 500.
	for (let i = 0; i < allowedTokens.length; i += 500) {
		const batch = allowedTokens.slice(i, i + 500)
		await messaging.sendEachForMulticast({
			tokens: batch,
			notification: title ? { title, body: messageBody } : { body: messageBody },
			data,
		})
	}

	// Log rate-limited sends per distinct user UID.
	if (maxPerUserPerDay != null && tokenTopic) {
		const day = todayUtcDateString()
		const payload = allowedUserUids.map((uid) => ({ user_uid: uid, token_topic: tokenTopic, day }))
		const { error: insertError } = await supabase.from('notification_push_send_log').insert(payload)
		if (insertError) return json({ error: insertError.message }, { status: 500 })
	}

	return json({ ok: true, notification_id: ensured.notificationId, sent_tokens: allowedTokens.length, sent_users: allowedUserUids.length })
}
