import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type FeaturedArtistRow = {
	id: string
	artist_id: string
	country_code: string | null
	priority: number | null
	is_active: boolean
	starts_at: string | null
	ends_at: string | null
	created_at: string
	updated_at: string
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function isMissingTableError(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { code?: unknown; message?: unknown; details?: unknown; hint?: unknown }
	const code = typeof e.code === 'string' ? e.code : null
	if (code === '42P01' || code === 'PGRST205') return true
	const msg = [e.message, e.details, e.hint]
		.map((x) => (typeof x === 'string' ? x : ''))
		.join(' ')
		.toLowerCase()
	return msg.includes('does not exist') || msg.includes('could not find the table')
}

export async function GET() {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })

	const canManage =
		ctx.admin.role === 'super_admin' ||
		ctx.admin.role === 'operations_admin' ||
		ctx.permissions.can_manage_artists
	if (!canManage) return json({ error: 'Forbidden' }, { status: 403 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	try {
		const { data, error } = await supabase
			.from('featured_artists')
			.select('id,artist_id,country_code,priority,is_active,starts_at,ends_at,created_at,updated_at')
			.order('is_active', { ascending: false })
			.order('priority', { ascending: false })
			.order('created_at', { ascending: false })
			.limit(250)
		if (error) {
			if (isMissingTableError(error)) {
				return json(
					{
						ok: false,
						error: 'missing_table_featured_artists',
						help:
							"Apply migration supabase/migrations/20260202120000_featured_artists.sql, then reload PostgREST schema cache (SQL: NOTIFY pgrst, 'reload schema';).",
					},
					{ status: 500 },
				)
			}
			return json({ ok: false, error: error.message ?? 'Query failed' }, { status: 500 })
		}
		return json(
			{ ok: true, featured_artists: (data ?? []) as unknown as FeaturedArtistRow[] },
			{ headers: { 'cache-control': 'no-store' } },
		)
	} catch (e) {
		if (isMissingTableError(e)) {
			return json(
				{
					ok: false,
					error: 'missing_table_featured_artists',
					help:
						"Apply migration supabase/migrations/20260202120000_featured_artists.sql, then reload PostgREST schema cache (SQL: NOTIFY pgrst, 'reload schema';).",
				},
				{ status: 500 },
			)
		}
		return json({ ok: false, error: e instanceof Error ? e.message : 'Query failed' }, { status: 500 })
	}
}
