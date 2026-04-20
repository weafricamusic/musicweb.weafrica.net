import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { DashboardShell } from '@/components/DashboardShell'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { UsersTable } from './UsersTable'
export const runtime = 'nodejs'

export default async function UsersPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	type UserRow = {
		uid: string
		name: string
		email: string | null
		phone: string | null
		avatarUrl: string | null
		disabled: boolean
		status: 'active' | 'blocked'
		region: string
		joinedAt: string | null
		searchText: string
	}

	let rows: UserRow[] = []
	let loadError: string | null = null
	try {
		const { users } = await getFirebaseAdminAuth().listUsers(250)
		const base = users.map((u) => {
			const claims = (u.customClaims ?? undefined) as Record<string, unknown> | undefined
			const claimRole = (claims?.admin_role ?? claims?.role ?? 'user') as string
			return {
				uid: u.uid,
				email: u.email ?? null,
				phone: u.phoneNumber ?? null,
				displayName: u.displayName ?? null,
				photoURL: (u.photoURL ?? null) as string | null,
				disabled: u.disabled,
				role: claimRole,
				joinedAt: u.metadata.creationTime ?? null,
			}
		})

		// Listener accounts only
		const listenerBase = base.filter((u) => (u.role ?? 'user') === 'user')

		// Best-effort profile merge from Supabase `users` table (may not exist / may be RLS-blocked)
		const supabase = createSupabaseServerClient()
		let profilesByUid = new Map<string, any>()
		try {
			const uids = listenerBase.map((u) => u.uid)
			if (uids.length) {
				const { data } = await supabase
					.from('users')
					.select('*')
					.in('firebase_uid', uids)
					.limit(250)
				;(data ?? []).forEach((p: any) => {
					const key = String(p.firebase_uid ?? p.uid ?? p.id ?? '')
					if (key) profilesByUid.set(key, p)
				})
			}
		} catch {
			profilesByUid = new Map()
		}

		rows = listenerBase.map((u) => {
			const p = profilesByUid.get(u.uid) as any | undefined
			const username = (p?.username ?? p?.handle ?? null) as string | null
			const displayName = (p?.display_name ?? p?.name ?? null) as string | null
			const name = username ?? displayName ?? u.displayName ?? u.email ?? u.uid
			const avatarUrl =
				(p?.avatar_url ?? p?.photo_url ?? p?.profile_image_url ?? u.photoURL ?? null) as string | null
			const regionRaw = (p?.region ?? p?.country ?? 'MW') as string
			const region = regionRaw.toUpperCase() === 'MALAWI' ? 'MW' : regionRaw.toUpperCase()
			const phone = (p?.phone ?? u.phone ?? null) as string | null
			const status: 'active' | 'blocked' = u.disabled ? 'blocked' : 'active'
			const searchText = [name, u.email, phone, u.uid].filter(Boolean).join(' | ')
			return {
				uid: u.uid,
				name,
				email: u.email,
				phone,
				avatarUrl,
				disabled: u.disabled,
				status,
				region,
				joinedAt: u.joinedAt,
				searchText,
			} satisfies UserRow
		})
	} catch (err) {
		loadError = err instanceof Error ? err.message : 'Unknown error'
	}

	if (loadError) {
		return (
			<DashboardShell title="Users">
				<p className="text-sm text-red-600 dark:text-red-400">Error loading users: {loadError}</p>
			</DashboardShell>
		)
	}

	return (
		<DashboardShell title="Users Management">
			<UsersTable users={rows} totalCount={rows.length} />
		</DashboardShell>
	)
}
