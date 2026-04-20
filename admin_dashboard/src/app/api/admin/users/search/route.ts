import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type AdminUserRole = 'consumer' | 'artist' | 'dj'

type SearchUserRow = {
	uid: string
	name: string
	email: string | null
	role: AdminUserRole
}

function normalizeRole(value: unknown): AdminUserRole {
	const v = String(value ?? '').trim().toLowerCase()
	if (v === 'artist') return 'artist'
	if (v === 'dj') return 'dj'
	return 'consumer'
}

function normalizeQuery(value: unknown): string {
	const raw = String(value ?? '').trim()
	if (!raw) return ''
	// Keep it URL-safe for Supabase `.or(...)` filter strings.
	return raw
		.replace(/[%]/g, ' ')
		.replace(/[,]/g, ' ')
		.replace(/\s+/g, ' ')
		.trim()
}

function normalizeRoleFilter(value: unknown): AdminUserRole | 'all' {
	const v = String(value ?? '').trim().toLowerCase()
	if (v === 'artist') return 'artist'
	if (v === 'dj') return 'dj'
	if (v === 'consumer') return 'consumer'
	return 'all'
}

function pickName(row: {
	display_name?: unknown
	full_name?: unknown
	username?: unknown
	email?: unknown
	id?: unknown
	firebase_uid?: unknown
}): string {
	const display = String(row.display_name ?? '').trim()
	if (display) return display
	const full = String(row.full_name ?? '').trim()
	if (full) return full
	const user = String(row.username ?? '').trim()
	if (user) return user
	const email = String(row.email ?? '').trim()
	if (email) return email
	const id = String(row.id ?? '').trim()
	if (id) return id
	const uid = String(row.firebase_uid ?? '').trim()
	if (uid) return uid
	return 'Unknown'
}

export async function GET(req: Request) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(adminCtx, 'can_manage_users')
	} catch {
		return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required to search users.' },
			{ status: 500 },
		)
	}

	const url = new URL(req.url)
	const q = normalizeQuery(url.searchParams.get('q'))
	const roleFilter = normalizeRoleFilter(url.searchParams.get('role'))
	if (!q || q.length < 2) return NextResponse.json({ ok: true, users: [] satisfies SearchUserRow[] })

	const like = `%${q}%`

	// Prefer `profiles` (id = Firebase UID, contains role + names).
	try {
		let query = supabase
			.from('profiles')
			.select('id,display_name,full_name,username,email,role,updated_at')
			.or(
				[
					`display_name.ilike.${like}`,
					`full_name.ilike.${like}`,
					`username.ilike.${like}`,
					`email.ilike.${like}`,
					`id.ilike.${like}`,
				].join(','),
			)
			.order('updated_at', { ascending: false })
			.limit(25)

		if (roleFilter !== 'all') query = query.eq('role', roleFilter)

		const { data, error } = await query
		if (error) throw error

		const users: SearchUserRow[] = (data ?? [])
			.map((row: any) => {
				const uid = String(row?.id ?? '').trim()
				if (!uid) return null
				const role = normalizeRole(row?.role)
				const email = typeof row?.email === 'string' ? row.email : null
				return {
					uid,
					name: pickName(row),
					email,
					role,
				} satisfies SearchUserRow
			})
			.filter(Boolean) as SearchUserRow[]

		return NextResponse.json({ ok: true, users })
	} catch {
		// fall through
	}

	// Fallback to `users` table (may not have role).
	try {
		const { data, error } = await supabase
			.from('users')
			.select('id,firebase_uid,username,email,created_at')
			.or([`firebase_uid.ilike.${like}`, `username.ilike.${like}`, `email.ilike.${like}`, `id::text.ilike.${like}`].join(','))
			.order('created_at', { ascending: false })
			.limit(25)
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })

		const users: SearchUserRow[] = (data ?? [])
			.map((row: any) => {
				const uid = String(row?.firebase_uid ?? row?.id ?? '').trim()
				if (!uid) return null
				const email = typeof row?.email === 'string' ? row.email : null
				return { uid, name: pickName(row), email, role: 'consumer' } satisfies SearchUserRow
			})
			.filter(Boolean) as SearchUserRow[]

		return NextResponse.json({ ok: true, users })
	} catch (e) {
		return NextResponse.json(
			{ error: e instanceof Error ? e.message : 'Failed to search users.' },
			{ status: 500 },
		)
	}
}
