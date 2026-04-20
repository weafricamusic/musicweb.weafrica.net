import 'server-only'

import { Buffer } from 'buffer'

function normalizeEnvOptional(name: string): string | undefined {
	const raw = process.env[name]
	if (!raw) return undefined
	const value = raw.trim().replace(/^['"]|['"]$/g, '')
	return value.length ? value : undefined
}

export type AgoraKickChannelResult =
	| { attempted: false; ok: false; error: string }
	| { attempted: true; ok: true; ruleId: number | null; status: number; response: unknown }
	| { attempted: true; ok: false; status?: number; error: string; responseText?: string }

export type AgoraDeleteKickingRuleResult =
	| { attempted: false; ok: false; error: string }
	| { attempted: true; ok: true; status: number; response: unknown }
	| { attempted: true; ok: false; status?: number; error: string; responseText?: string }

function getAgoraCustomerBasicAuth(): { appId: string; authHeader: string } | null {
	const appId = normalizeEnvOptional('AGORA_APP_ID')
	const customerId = normalizeEnvOptional('AGORA_CUSTOMER_ID')
	const customerSecret = normalizeEnvOptional('AGORA_CUSTOMER_SECRET')
	if (!appId) return null
	if (!customerId || !customerSecret) return null

	const basic = Buffer.from(`${customerId}:${customerSecret}`).toString('base64')
	return { appId, authHeader: `Basic ${basic}` }
}

/**
 * Real Agora RTC channel stop (closest available):
 * Creates a "kicking rule" that bans `join_channel` for the channel name.
 * This kicks current users and prevents re-join until the rule expires.
 */
export async function tryKickAgoraChannel(input: {
	channelName: string
	seconds?: number
}): Promise<AgoraKickChannelResult> {
	const auth = getAgoraCustomerBasicAuth()
	if (!auth) {
		return {
			attempted: false,
			ok: false,
			error:
				'Missing Agora REST credentials. Set AGORA_APP_ID, AGORA_CUSTOMER_ID, and AGORA_CUSTOMER_SECRET to enable real stop.',
		}
	}

	const channelName = input.channelName.trim()
	if (!channelName) {
		return { attempted: true, ok: false, error: 'Missing channelName' }
	}

	const timeInSeconds = Number.isFinite(input.seconds) ? Math.max(1, Math.floor(input.seconds!)) : 600

	try {
		const res = await fetch('https://api.agora.io/dev/v1/kicking-rule', {
			method: 'POST',
			headers: {
				accept: 'application/json',
				authorization: auth.authHeader,
				'content-type': 'application/json',
			},
			body: JSON.stringify({
				appid: auth.appId,
				cname: channelName,
				privileges: ['join_channel'],
				time_in_seconds: timeInSeconds,
			}),
		})

		const text = await res.text().catch(() => '')
		let parsed: unknown = null
		try {
			parsed = text ? (JSON.parse(text) as unknown) : null
		} catch {
			parsed = text
		}

		if (!res.ok) {
			return {
				attempted: true,
				ok: false,
				status: res.status,
				error: `Agora kicking-rule failed (${res.status})`,
				responseText: text,
			}
		}

		const ruleId =
			parsed && typeof parsed === 'object' && 'id' in (parsed as any) ? Number((parsed as any).id) : null

		return { attempted: true, ok: true, ruleId: Number.isFinite(ruleId) ? ruleId : null, status: res.status, response: parsed }
	} catch (e) {
		return {
			attempted: true,
			ok: false,
			error: e instanceof Error ? e.message : 'Agora request failed',
		}
	}
}

export async function tryDeleteAgoraKickingRule(input: { ruleId: number }): Promise<AgoraDeleteKickingRuleResult> {
	const auth = getAgoraCustomerBasicAuth()
	if (!auth) {
		return {
			attempted: false,
			ok: false,
			error:
				'Missing Agora REST credentials. Set AGORA_APP_ID, AGORA_CUSTOMER_ID, and AGORA_CUSTOMER_SECRET to manage rules.',
		}
	}

	const ruleId = Number(input.ruleId)
	if (!Number.isFinite(ruleId)) {
		return { attempted: true, ok: false, error: 'Invalid ruleId' }
	}

	try {
		const res = await fetch('https://api.agora.io/dev/v1/kicking-rule', {
			method: 'DELETE',
			headers: {
				accept: 'application/json',
				authorization: auth.authHeader,
				'content-type': 'application/json',
			},
			body: JSON.stringify({ appid: auth.appId, id: ruleId }),
		})

		const text = await res.text().catch(() => '')
		let parsed: unknown = null
		try {
			parsed = text ? (JSON.parse(text) as unknown) : null
		} catch {
			parsed = text
		}

		if (!res.ok) {
			return {
				attempted: true,
				ok: false,
				status: res.status,
				error: `Agora delete kicking-rule failed (${res.status})`,
				responseText: text,
			}
		}

		return { attempted: true, ok: true, status: res.status, response: parsed }
	} catch (e) {
		return {
			attempted: true,
			ok: false,
			error: e instanceof Error ? e.message : 'Agora request failed',
		}
	}
}
