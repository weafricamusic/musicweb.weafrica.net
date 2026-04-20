import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

type CountResult = {
	count: number | null
	// PostgREST error code (e.g. 42P01 table missing, 42703 column missing)
	errorCode?: string
	errorMessage?: string
}

function isPostgrestErrorLike(value: unknown): value is { code?: string; message?: string } {
	return !!value && typeof value === 'object' && ('code' in value || 'message' in value)
}

async function tryCountEq(
	supabase: SupabaseClient,
	table: string,
	column: string,
	value: string | number | boolean | null,
): Promise<CountResult> {
	try {
		const query = supabase.from(table).select('id', { head: true, count: 'exact' })
		const { count, error } = value === null ? await query.is(column, null) : await query.eq(column, value)
		if (error) {
			const code = isPostgrestErrorLike(error) ? (error.code as string | undefined) : undefined
			const message = isPostgrestErrorLike(error) ? (error.message as string | undefined) : undefined
			return { count: null, errorCode: code, errorMessage: message }
		}
		return { count: typeof count === 'number' ? count : 0 }
	} catch (e) {
		return { count: null, errorMessage: e instanceof Error ? e.message : 'Count failed' }
	}
}

async function countPendingCreatorsByApproved(supabase: SupabaseClient, table: string): Promise<number | null> {
	const primary = await tryCountEq(supabase, table, 'approved', false)
	if (typeof primary.count === 'number') return primary.count
	// Fallback: some schemas track creator approval as status.
	if (primary.errorCode === '42703') {
		const fallback = await tryCountEq(supabase, table, 'status', 'pending')
		if (typeof fallback.count === 'number') return fallback.count
	}
	// Missing table or other error: treat as unknown.
	return null
}

async function countPendingSongs(supabase: SupabaseClient): Promise<number | null> {
	// Primary schema used throughout the admin dashboard.
	const primary = await tryCountEq(supabase, 'songs', 'approved', false)
	if (typeof primary.count === 'number') return primary.count
	// Some older schemas used different names.
	if (primary.errorCode === '42703') {
		const alt = await tryCountEq(supabase, 'songs', 'is_approved', false)
		if (typeof alt.count === 'number') return alt.count
	}
	return null
}

/**
 * Returns total number of items waiting for approval.
 *
 * Scope (best-effort): artists + DJs + tracks (songs).
 * Returns null if it cannot determine a reliable count (e.g. missing tables or RLS).
 */
export async function getPendingApprovalsCount(supabase: SupabaseClient): Promise<number | null> {
	const [artists, djs, songs] = await Promise.all([
		countPendingCreatorsByApproved(supabase, 'artists'),
		countPendingCreatorsByApproved(supabase, 'djs'),
		countPendingSongs(supabase),
	])

	const values = [artists, djs, songs].filter((v): v is number => typeof v === 'number')
	if (!values.length) return null
	return values.reduce((sum, v) => sum + v, 0)
}
