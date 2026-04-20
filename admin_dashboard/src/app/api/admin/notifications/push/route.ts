import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getFirebaseAdminMessaging } from '@/lib/firebase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function canManagePush(ctx: Awaited<ReturnType<typeof getAdminContext>>) {
	if (!ctx) return false
	return ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin'
}

function isMissingTable(err: any): boolean {
	const message = String(err?.message ?? '')
	const code = String(err?.code ?? '')
	return code === '42P01' || code === 'PGRST205' || message.toLowerCase().includes('schema cache') || message.toLowerCase().includes('could not find the table')
}

function ensureNotificationId(data: unknown, id: string): Record<string, unknown> {
	const base: Record<string, unknown> = data && typeof data === 'object' ? (data as any) : {}
	const existing = (base as any).notification_id
	if (existing != null && String(existing).trim()) return base
	return { ...base, notification_id: id }
}

const TABLE = 'notification_push_messages' as const
const TOKENS_TABLE = 'notification_device_tokens' as const

type Row = {
	id: string
	title: string | null
	body: string
	topic: string
	delivery?: 'tokens' | 'fcm_topic'
	token_topic?: string | null
	target_country_code?: string | null
	target_role?: 'consumers' | 'artists' | 'djs' | null
	target_user_uid?: string | null
	data: Record<string, unknown>
	status: 'draft' | 'sent' | 'failed' | 'archived'
	sent_at: string | null
	error: string | null
	created_by: string | null
	created_at: string
	updated_at: string
}

export async function GET() {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	if (!canManagePush(ctx)) return json({ error: 'Forbidden' }, { status: 403 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data, error } = await supabase.from(TABLE).select('*').order('created_at', { ascending: false }).limit(100)
	if (error) {
		if (isMissingTable(error)) {
			return json(
				{
					error:
						`Missing table ${TABLE}. Apply migrations 20260126120000_notifications_push.sql and 20260128120000_notifications_push_targeting.sql then reload the Supabase schema cache.`,
				},
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}
	return json({ ok: true, messages: (data ?? []) as unknown as Row[] })
}

type CreateBody = {
	title?: string | null
	body: string
	// Legacy meaning: FCM topic. In token mode we force topic='tokens_all' and use token_topic.
	topic?: string
	delivery?: 'tokens' | 'fcm_topic'
	// Token-mode targeting
	token_topic?: string | null
	target_country_code?: string | null
	target_role?: 'consumers' | 'artists' | 'djs' | null
	target_user_uid?: string | null
	data?: Record<string, unknown>
	send_now?: boolean
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	if (!canManagePush(ctx)) return json({ error: 'Forbidden' }, { status: 403 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as CreateBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })

	const text = String(body.body ?? '').trim()
	if (!text) return json({ error: 'Body is required' }, { status: 400 })

	const requestedTopic = String(body.topic ?? 'all').trim() || 'all'
	const requestedDelivery = body.delivery === 'tokens' || body.delivery === 'fcm_topic' ? body.delivery : undefined
	const inferredDelivery: 'tokens' | 'fcm_topic' = requestedTopic === 'tokens_all' ? 'tokens' : 'fcm_topic'
	const delivery: 'tokens' | 'fcm_topic' = requestedDelivery ?? inferredDelivery

	const tokenTopic = body.token_topic == null ? null : String(body.token_topic).trim() || null
	const targetCountry = body.target_country_code == null ? null : String(body.target_country_code).trim().toLowerCase() || null
	const targetRole = body.target_role == null ? null : body.target_role
	const targetUserUid = body.target_user_uid == null ? null : String(body.target_user_uid).trim() || null

	// In token mode, we always send via token registry. Keep topic stable for legacy send logic.
	const topic = delivery === 'tokens' ? 'tokens_all' : requestedTopic

	const payload = {
		title: body.title == null ? null : String(body.title).trim() || null,
		body: text,
		topic,
		delivery,
		token_topic: tokenTopic,
		target_country_code: targetCountry,
		target_role: targetRole,
		target_user_uid: targetUserUid,
		data: body.data && typeof body.data === 'object' ? body.data : {},
		status: 'draft' as const,
		created_by: ctx.admin.email,
		updated_at: new Date().toISOString(),
	}

	const { data: created, error } = await supabase.from(TABLE).insert(payload).select('*').single()
	if (error) {
		if (isMissingTable(error)) {
			return json(
				{
					error:
						`Missing table ${TABLE}. Apply migrations 20260126120000_notifications_push.sql and 20260128120000_notifications_push_targeting.sql then reload the Supabase schema cache.`,
				},
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	let row = created as Row

	// Ensure analytics key is present for downstream routing/metrics.
	const ensured = ensureNotificationId((row as any).data, row.id)
	if (ensured !== (row as any).data) {
		const { data: updatedRow, error: updateRowError } = await supabase
			.from(TABLE)
			.update({ data: ensured, updated_at: new Date().toISOString() })
			.eq('id', row.id)
			.select('*')
			.single()
		if (!updateRowError && updatedRow) row = updatedRow as Row
	}

	// Optional send now
	if (body.send_now) {
		const sent = await sendNowInternal({ ctx, id: row.id })
		if (!sent.ok) return json({ error: sent.error }, { status: sent.status })
		row = sent.message
	}

	await logAdminAction({
		ctx,
		action: 'notifications.push.create',
		target_type: 'notification_push_message',
		target_id: row.id,
		before_state: null,
		after_state: row as any,
		meta: { module: 'notifications', channel: 'push', delivery: (row as any).delivery ?? delivery },
		req,
	})

	return json({ ok: true, message: row })
}

type PatchBody =	| { action: 'send_now'; id: string }
	| { action: 'archive'; id: string }

export async function PATCH(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	if (!canManagePush(ctx)) return json({ error: 'Forbidden' }, { status: 403 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })

	if (body.action === 'send_now') {
		const sent = await sendNowInternal({ ctx, id: body.id })
		if (!sent.ok) return json({ error: sent.error }, { status: sent.status })

		await logAdminAction({
			ctx,
			action: 'notifications.push.send',
			target_type: 'notification_push_message',
			target_id: body.id,
			before_state: null,
			after_state: sent.message as any,
			meta: { module: 'notifications', channel: 'push', topic: sent.message.topic, delivery: (sent.message as any).delivery },
			req,
		})

		return json({ ok: true, message: sent.message })
	}

	if (body.action === 'archive') {
		const { data, error } = await supabase
			.from(TABLE)
			.update({ status: 'archived', updated_at: new Date().toISOString() })
			.eq('id', body.id)
			.select('*')
			.single()
		if (error) return json({ error: error.message }, { status: 500 })

		await logAdminAction({
			ctx,
			action: 'notifications.push.archive',
			target_type: 'notification_push_message',
			target_id: body.id,
			before_state: null,
			after_state: data as any,
			meta: { module: 'notifications', channel: 'push' },
			req,
		})

		return json({ ok: true, message: data as Row })
	}

	return json({ error: 'Invalid action' }, { status: 400 })
}


type SendNowResult = { ok: true; message: Row } | { ok: false; error: string; status: number }

async function sendNowInternal(args: { ctx: NonNullable<Awaited<ReturnType<typeof getAdminContext>>>; id: string }): Promise<SendNowResult> {
	const { id } = args
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return { ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.', status: 500 }

	const { data: row, error: loadError } = await supabase.from(TABLE).select('*').eq('id', id).single()
	if (loadError) return { ok: false, error: loadError.message, status: 500 }

	if (!row) return { ok: false, error: 'Not found', status: 404 }
	if (row.status === 'sent') return { ok: true, message: row as Row }
	if (row.status === 'archived') return { ok: false, error: 'Archived messages cannot be sent', status: 400 }

	try {
		const messaging = getFirebaseAdminMessaging()
		const title = row.title ? String(row.title) : undefined
		const body = String(row.body)
		const topic = String(row.topic || 'all')
		const delivery: 'tokens' | 'fcm_topic' = (row as any).delivery === 'tokens' ? 'tokens' : 'fcm_topic'
		const tokenTopicRaw = (row as any).token_topic
		const tokenTopic = tokenTopicRaw == null ? null : String(tokenTopicRaw).trim() || null
		const targetCountryRaw = (row as any).target_country_code
		const targetCountry = targetCountryRaw == null ? null : String(targetCountryRaw).trim().toLowerCase() || null
		const targetRole = (row as any).target_role as Row['target_role']
		const targetUserUidRaw = (row as any).target_user_uid
		const targetUserUid = targetUserUidRaw == null ? null : String(targetUserUidRaw).trim() || null

		const dataWithId = ensureNotificationId((row as any).data, id)

		// FCM data values must be strings.
		const data: Record<string, string> = {}
		if (dataWithId && typeof dataWithId === 'object') {
			for (const [k, v] of Object.entries(dataWithId as Record<string, unknown>)) {
				if (v == null) continue
				data[String(k)] = typeof v === 'string' ? v : JSON.stringify(v)
			}
		}

		if (delivery === 'tokens' || topic === 'tokens_all') {
			let q = supabase.from(TOKENS_TABLE).select('token').order('last_seen_at', { ascending: false }).limit(5000)

			if (targetUserUid) {
				q = q.eq('user_uid', targetUserUid)
			} else {
				if (targetCountry) q = q.eq('country_code', targetCountry)
				if (targetRole) q = q.contains('topics', [targetRole])
				if (tokenTopic && tokenTopic !== 'all') q = q.contains('topics', [tokenTopic])
			}

			const { data: tokenRows, error: tokenError } = await q
			if (tokenError) return { ok: false, error: tokenError.message, status: 500 }
			const tokens = (tokenRows ?? [])
				.map((r: any) => String(r?.token ?? '').trim())
				.filter(Boolean)
			if (!tokens.length) return { ok: false, error: 'No registered device tokens found yet.', status: 400 }

			// Multicast limit is 500.
			for (let i = 0; i < tokens.length; i += 500) {
				const batch = tokens.slice(i, i + 500)
				await messaging.sendEachForMulticast({
					tokens: batch,
					notification: title ? { title, body } : { body },
					data,
				})
			}
		} else {
			await messaging.send({
				topic,
				notification: title ? { title, body } : { body },
				data,
			})
		}

		const { data: updated, error: updateError } = await supabase
			.from(TABLE)
			.update({ status: 'sent', sent_at: new Date().toISOString(), error: null, updated_at: new Date().toISOString() })
			.eq('id', id)
			.select('*')
			.single()
		if (updateError) return { ok: false, error: updateError.message, status: 500 }

		return { ok: true, message: updated as Row }
	} catch (e: unknown) {
		const msg = e instanceof Error ? e.message : 'Send failed'
		try {
			await supabase
				.from(TABLE)
				.update({ status: 'failed', error: msg, updated_at: new Date().toISOString() })
				.eq('id', id)
		} catch {
			// ignore
		}
		return { ok: false, error: msg, status: 500 }
	}
}
