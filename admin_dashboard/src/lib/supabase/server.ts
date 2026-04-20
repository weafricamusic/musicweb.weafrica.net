import { createClient } from '@supabase/supabase-js'

export type SupabaseServerEnvDebug = {
	urlHost: string
	keyMode: 'service_role' | 'anon'
	serviceRolePresent: boolean
	serviceRoleLooksPlaceholder: boolean
	serviceRoleKeyLen?: number
	serviceRoleJwtRole?: string
	serviceRoleJwtRef?: string
	urlRef?: string
	refMismatch?: boolean
}

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
	const value = raw.trim().replace(/^['"]|['"]$/g, '')
	return value.length ? value : undefined
}

function normalizeSupabaseUrlOptional(name: string): string | undefined {
	const raw = normalizeEnvOptional(name)
	if (!raw) return undefined
	// Remove accidental whitespace/newlines from env providers.
	const compact = raw.replace(/\s+/g, '')
	if (!compact) return undefined

	// Supabase client requires an explicit http(s) URL.
	if (compact.startsWith('http://') || compact.startsWith('https://')) return compact

	// Common mistake: setting host without scheme.
	// If it looks like a Supabase host, assume https.
	if (/^[a-z0-9-]+\.supabase\.(co|in)$/i.test(compact)) {
		return `https://${compact}`
	}

	return compact
}

function normalizeKeyOptional(name: string): string | undefined {
	const raw = normalizeEnvOptional(name)
	if (!raw) return undefined
	// Supabase keys are JWT-like strings; remove accidental whitespace/newlines from env providers.
	const compact = raw.replace(/\s+/g, '')
	return compact.length ? compact : undefined
}

function normalizeEnvRequired(name: string): string {
	const value = normalizeEnvOptional(name)
	if (!value) throw new Error(`Missing ${name}`)
	return value
}

function normalizeSupabaseUrlRequired(name: string): string {
	const value = normalizeSupabaseUrlOptional(name)
	if (!value) throw new Error(`Missing ${name}`)
	// Validate early so server errors are descriptive.
	try {
		const u = new URL(value)
		if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new Error('Must be a valid HTTP or HTTPS URL')
	} catch (e) {
		const msg = e instanceof Error ? e.message : 'Must be a valid HTTP or HTTPS URL'
		throw new Error(`Invalid ${name}: ${msg}`)
	}
	return value
}

export function getSupabaseServerEnvDebug(): SupabaseServerEnvDebug {
	const url = normalizeSupabaseUrlRequired('NEXT_PUBLIC_SUPABASE_URL')
	const anonKey = normalizeKeyOptional('NEXT_PUBLIC_SUPABASE_ANON_KEY') ?? normalizeEnvRequired('NEXT_PUBLIC_SUPABASE_ANON_KEY')
	const serviceKey = normalizeKeyOptional('SUPABASE_SERVICE_ROLE_KEY')

	const serviceRoleLooksPlaceholder =
		!serviceKey || /\.\.\.|yourservicerolekey|placeholder/i.test(serviceKey)
	const keyToUse = serviceRoleLooksPlaceholder ? anonKey : serviceKey

	let urlHost = url
	let urlRef: string | undefined
	try {
		const u = new URL(url)
		urlHost = u.host
		// For https://<ref>.supabase.co, ref is the first label.
		urlRef = u.host.split('.')[0]
	} catch {
		// ignore
	}

	const servicePayload = serviceKey ? tryParseJwtPayload(serviceKey) : null
	const serviceRoleJwtRole = typeof servicePayload?.role === 'string' ? (servicePayload.role as string) : undefined
	const serviceRoleJwtRef = typeof servicePayload?.ref === 'string' ? (servicePayload.ref as string) : undefined
	const refMismatch = Boolean(urlRef && serviceRoleJwtRef && urlRef !== serviceRoleJwtRef)

	return {
		urlHost,
		keyMode: keyToUse === anonKey ? 'anon' : 'service_role',
		serviceRolePresent: Boolean(serviceKey),
		serviceRoleLooksPlaceholder,
		serviceRoleKeyLen: serviceKey ? serviceKey.length : undefined,
		serviceRoleJwtRole,
		serviceRoleJwtRef,
		urlRef,
		refMismatch,
	}
}

export function createSupabaseServerClient() {
	const url = normalizeSupabaseUrlRequired('NEXT_PUBLIC_SUPABASE_URL')
	const anonKey = normalizeKeyOptional('NEXT_PUBLIC_SUPABASE_ANON_KEY') ?? normalizeEnvRequired('NEXT_PUBLIC_SUPABASE_ANON_KEY')
	const serviceKey = normalizeKeyOptional('SUPABASE_SERVICE_ROLE_KEY')

	const looksLikePlaceholder = !serviceKey || /\.\.\.|yourservicerolekey|placeholder/i.test(serviceKey)
	if (looksLikePlaceholder && process.env.NODE_ENV === 'production') {
		throw new Error(
			'SUPABASE_SERVICE_ROLE_KEY is missing/placeholder in production. Set it (server-only) to ensure server queries/admin pages can bypass RLS.',
		)
	}
	const keyToUse = looksLikePlaceholder ? anonKey : serviceKey

	if (looksLikePlaceholder) {
		// Avoid flooding logs during server renders.
		// @ts-expect-error - global flag (not part of lib typings)
		globalThis.__SUPABASE_SERVICE_ROLE_WARNED__ = globalThis.__SUPABASE_SERVICE_ROLE_WARNED__ ?? false
		// @ts-expect-error - global flag (not part of lib typings)
		if (!globalThis.__SUPABASE_SERVICE_ROLE_WARNED__) {
			console.warn(
				'⚠️  SUPABASE_SERVICE_ROLE_KEY is missing/placeholder; falling back to NEXT_PUBLIC_SUPABASE_ANON_KEY for server queries.'
			)
			// @ts-expect-error - global flag (not part of lib typings)
			globalThis.__SUPABASE_SERVICE_ROLE_WARNED__ = true
		}
	}

	return createClient(url, keyToUse, { auth: { persistSession: false, autoRefreshToken: false } })
}
