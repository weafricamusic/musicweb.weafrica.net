import 'server-only'

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

function normalizeEnvOptional(name: string): string | undefined {
	const raw = process.env[name]
	if (!raw) return undefined
	const value = raw.trim().replace(/^['"]|['"]$/g, '')
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

function normalizeKeyRequired(name: string): string {
	const raw = normalizeEnvOptional(name)
	if (!raw) throw new Error(`Missing ${name}`)
	const compact = raw.replace(/\s+/g, '')
	if (!compact) throw new Error(`Missing ${name}`)
	return compact
}

/**
 * Creates a Supabase client that ALWAYS uses the anon key.
 *
 * Use this for public consumer endpoints where RLS should apply.
 */
export function createSupabasePublicClient(): SupabaseClient {
	const url = normalizeSupabaseUrlRequired('NEXT_PUBLIC_SUPABASE_URL')
	const anonKey = normalizeKeyRequired('NEXT_PUBLIC_SUPABASE_ANON_KEY')
	return createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
}

export function tryCreateSupabasePublicClient(): SupabaseClient | null {
	try {
		return createSupabasePublicClient()
	} catch {
		return null
	}
}
