import 'server-only'

import { createHmac } from 'node:crypto'

type StopWebhookPayload = {
	event: 'live_stream.stop'
	streamId: string
	channelName: string
	reason: string | null
	requestedBy: { uid: string; email: string | null }
	ts: string
}

function normalizeEnvOptional(name: string): string | undefined {
	const raw = process.env[name]
	if (!raw) return undefined
	const value = raw.trim().replace(/^['"]|['"]$/g, '')
	return value.length ? value : undefined
}

function sign(secret: string, body: string): string {
	return createHmac('sha256', secret).update(body).digest('hex')
}

/**
 * Best-effort: calls your own backend (Cloud Function/API) that can actually terminate Agora channels.
 *
 * Env:
 * - LIVE_STREAM_STOP_WEBHOOK_URL
 * - LIVE_STREAM_STOP_WEBHOOK_SECRET (optional but recommended)
 */
export async function tryNotifyLiveStreamStop(input: {
	streamId: string
	channelName: string
	reason: string | null
	requestedBy: { uid: string; email: string | null }
}): Promise<{ ok: boolean; status?: number; error?: string }> {
	const url = normalizeEnvOptional('LIVE_STREAM_STOP_WEBHOOK_URL')
	if (!url) return { ok: false, error: 'LIVE_STREAM_STOP_WEBHOOK_URL not configured' }

	const secret = normalizeEnvOptional('LIVE_STREAM_STOP_WEBHOOK_SECRET')
	const payload: StopWebhookPayload = {
		event: 'live_stream.stop',
		streamId: input.streamId,
		channelName: input.channelName,
		reason: input.reason,
		requestedBy: input.requestedBy,
		ts: new Date().toISOString(),
	}

	const body = JSON.stringify(payload)
	const headers: Record<string, string> = {
		'content-type': 'application/json',
		'x-weafrica-event': payload.event,
	}
	if (secret) {
		headers['x-weafrica-signature'] = sign(secret, body)
		headers['x-weafrica-signature-alg'] = 'hmac-sha256-hex'
	}

	try {
		const res = await fetch(url, { method: 'POST', headers, body })
		if (!res.ok) {
			const text = await res.text().catch(() => '')
			return { ok: false, status: res.status, error: text || `Webhook failed (${res.status})` }
		}
		return { ok: true, status: res.status }
	} catch (e) {
		return { ok: false, error: e instanceof Error ? e.message : 'Webhook error' }
	}
}
