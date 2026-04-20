import 'server-only'

import { createSupabaseAdminClient, tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { createSupabaseServerClient } from '@/lib/supabase/server'

function warnOnce(message: string) {
	// Avoid flooding logs during server renders.
	// @ts-expect-error - global flag (not part of lib typings)
	globalThis.__SUPABASE_ADMIN_FALLBACK_WARNED__ = globalThis.__SUPABASE_ADMIN_FALLBACK_WARNED__ ?? false
	// @ts-expect-error - global flag (not part of lib typings)
	if (!globalThis.__SUPABASE_ADMIN_FALLBACK_WARNED__) {
		console.warn(message)
		// @ts-expect-error - global flag (not part of lib typings)
		globalThis.__SUPABASE_ADMIN_FALLBACK_WARNED__ = true
	}
}

/**
 * Returns a Supabase client suitable for server usage.
 *
 * - In production, this is strict and requires `SUPABASE_SERVICE_ROLE_KEY`.
 * - In dev, if the service role key is missing/placeholder, it falls back to the server client
 *   (which may use the anon key) so pages can render with partial/limited data.
 */
export function getSupabaseAdmin() {
	const admin = tryCreateSupabaseAdminClient()
	if (admin) return admin

	if (process.env.NODE_ENV === 'production') {
		// Keep production strict so we fail fast when misconfigured.
		return createSupabaseAdminClient()
	}

	warnOnce(
		'⚠️  SUPABASE_SERVICE_ROLE_KEY is missing/placeholder; getSupabaseAdmin() is falling back to createSupabaseServerClient() (anon key). Admin writes and RLS-bypassing reads will fail until the service role key is configured.'
	)
	return createSupabaseServerClient()
}

/** Strict: always requires `SUPABASE_SERVICE_ROLE_KEY`. Prefer for admin mutations. */
export function getSupabaseAdminStrict() {
	return createSupabaseAdminClient()
}
