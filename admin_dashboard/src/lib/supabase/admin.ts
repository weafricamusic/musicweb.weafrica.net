import 'server-only'

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

function base64UrlDecode(input: string): string {
	const normalized = input.replace(/-/g, '+').replace(/_/g, '/')
	const padLen = (4 - (normalized.length % 4)) % 4
	const padded = normalized + '='.repeat(padLen)
	return Buffer.from(padded, 'base64').toString('utf8')
}

function tryParseJwtPayload(value: string): Record<string, unknown> | null {
	const parts = value.split('.')
	if (parts.length !== 3) return null
	try {
		const json = base64UrlDecode(parts[1] ?? '')
		const payload = JSON.parse(json)
		return payload && typeof payload === 'object' ? (payload as Record<string, unknown>) : null
	} catch {
		return null
	}
}

function normalizeEnvOptional(name: string): string | undefined {
	const raw = process.env[name]
	if (!raw) return undefined
	const value = raw
		.trim()
		.replace(/^['"]|['"]$/g, '')
		.replace(/\\r/g, '')
		.replace(/\\n/g, '')
	return value.length ? value : undefined
}

function normalizeSupabaseUrlRequired(name: string): string {
	const raw = normalizeEnvOptional(name)
	if (!raw) throw new Error(`Missing ${name}`)
	const compact = raw.replace(/\s+/g, '')
	if (compact.startsWith('http://') || compact.startsWith('https://')) return compact
	if (/^[a-z0-9-]+\.supabase\.(co|in)$/i.test(compact)) return `https://${compact}`
	// Validate early so errors are descriptive.
	try {
		new URL(compact)
	} catch {
		throw new Error(`Invalid ${name}: Must be a valid HTTP or HTTPS URL`)
	}
	return compact
}

function normalizeEnvRequired(name: string): string {
	const value = normalizeEnvOptional(name)
	if (!value) throw new Error(`Missing ${name}`)
	return value
}

function looksLikePlaceholder(value: string | undefined): boolean {
	if (!value) return true
	const v = value.toLowerCase()
	return v.includes('...') || v.includes('yourservicerolekey') || v.includes('placeholder')
}

export function createSupabaseAdminClient(): SupabaseClient {
	const url = normalizeSupabaseUrlRequired('NEXT_PUBLIC_SUPABASE_URL')
	const serviceKey = normalizeEnvOptional('SUPABASE_SERVICE_ROLE_KEY')

	if (!serviceKey || looksLikePlaceholder(serviceKey)) {
		throw new Error(
			'SUPABASE_SERVICE_ROLE_KEY is missing/placeholder. Set it to enable admin writes & admin_activity logging.'
		)
	}

	// Guard against common misconfigurations where an anon key (or wrong-project key)
	// is accidentally set as SUPABASE_SERVICE_ROLE_KEY; this otherwise surfaces as confusing RLS errors.
	const payload = tryParseJwtPayload(serviceKey)
	if (!payload) {
		throw new Error(
			'SUPABASE_SERVICE_ROLE_KEY is not a valid JWT. Make sure you pasted the Service Role key (not the anon key) from Supabase Project Settings → API.'
		)
	}
	const role = typeof payload.role === 'string' ? (payload.role as string) : undefined
	if (role !== 'service_role') {
		throw new Error(
			`SUPABASE_SERVICE_ROLE_KEY does not appear to be a service-role key (jwt role=${role ?? 'unknown'}). Use the "service_role" key, not the anon key.`
		)
	}
	const keyRef = typeof payload.ref === 'string' ? (payload.ref as string) : undefined
	if (keyRef) {
		let urlRef: string | undefined
		try {
			const u = new URL(url)
			urlRef = u.host.split('.')[0]
		} catch {
			urlRef = undefined
		}
		if (urlRef && urlRef !== keyRef) {
			throw new Error(
				`SUPABASE_SERVICE_ROLE_KEY belongs to a different Supabase project (key ref=${keyRef}, url ref=${urlRef}). Fix NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY pairing.`
			)
		}
	}

	return createClient(url, serviceKey, {
		auth: { persistSession: false, autoRefreshToken: false },
	})
}

export function tryCreateSupabaseAdminClient(): SupabaseClient | null {
	try {
		return createSupabaseAdminClient()
	} catch {
		return null
	}
}
