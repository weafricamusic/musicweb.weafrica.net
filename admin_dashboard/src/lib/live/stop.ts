import 'server-only'

function normalizeEnvOptional(name: string): string | undefined {
	const raw = process.env[name]
	if (!raw) return undefined
	const value = raw.trim().replace(/^['"]|['"]$/g, '')
	return value.length ? value : undefined
}

export type StopStreamRequest = {
	streamId: string
	channelName: string
	adminEmail: string | null
	reason: string | null
}

export type StopStreamResult =
	| { attempted: false; skipped: true; message: string }
	| { attempted: true; ok: true; status: number; bodyText?: string }
	| { attempted: true; ok: false; status?: number; error: string; bodyText?: string }

/**
 * Best-effort hook for stopping an Agora live stream.
 *
 * This admin repo does NOT hardcode Agora REST endpoints (docs are hard to scrape reliably).
 * Instead, you can point to your own secure backend (Cloud Function/API) that performs:
 * - Agora channel ban/kick/end
 * - push notification to streamer
 *
 * Env:
 * - LIVE_STREAM_STOP_WEBHOOK_URL (required to enable)
 * - LIVE_STREAM_STOP_WEBHOOK_SECRET (optional shared secret; sent as x-webhook-secret)
 * - AGORA_APP_ID (included in payload for convenience)
 */
export async function tryStopStreamViaWebhook(input: StopStreamRequest): Promise<StopStreamResult> {
	const url = normalizeEnvOptional('LIVE_STREAM_STOP_WEBHOOK_URL')
	if (!url) {
		return { attempted: false, skipped: true, message: 'LIVE_STREAM_STOP_WEBHOOK_URL not configured' }
	}

	const secret = normalizeEnvOptional('LIVE_STREAM_STOP_WEBHOOK_SECRET')
	const agoraAppId = normalizeEnvOptional('AGORA_APP_ID')

	try {
		const res = await fetch(url, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				...(secret ? { 'x-webhook-secret': secret } : {}),
			},
			body: JSON.stringify({
				action: 'stop_stream',
				streamId: input.streamId,
				channelName: input.channelName,
				reason: input.reason,
				adminEmail: input.adminEmail,
				agoraAppId,
			}),
		})

		const bodyText = await res.text().catch(() => '')
		if (!res.ok) {
			return { attempted: true, ok: false, status: res.status, error: `Webhook failed (${res.status})`, bodyText }
		}
		return { attempted: true, ok: true, status: res.status, bodyText }
	} catch (e) {
		return { attempted: true, ok: false, error: e instanceof Error ? e.message : 'Webhook request failed' }
	}
}
