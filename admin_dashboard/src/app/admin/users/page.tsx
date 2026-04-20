import { getUsers } from './actions'
import { UsersTable } from './UsersTable'
import { getAdminContext } from '@/lib/admin/session'

export const dynamic = 'force-dynamic'

export default async function UsersPage() {
	const ctx = await getAdminContext().catch(() => null)
	let users: Awaited<ReturnType<typeof getUsers>> = []
	let loadError: string | null = null
	try {
		users = await getUsers()
	} catch (e) {
		loadError = e instanceof Error ? e.message : 'Failed to load users'
	}

	return (
		<div className="space-y-4">
			{loadError ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					<div className="font-medium">User list unavailable</div>
					<div className="mt-1 opacity-90">{loadError}</div>
					<div className="mt-2 opacity-90">
						If this is Vercel: set <span className="rounded bg-black/20 px-1">ADMIN_BACKEND_BASE_URL</span>,{' '}
						<span className="rounded bg-black/20 px-1">NEXT_PUBLIC_FIREBASE_API_KEY</span>, and a Firebase admin credential such as{' '}
						<span className="rounded bg-black/20 px-1">FIREBASE_SERVICE_ACCOUNT_BASE64</span>, then redeploy.
					</div>
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<UsersTable users={users} canManageFinance={!!ctx?.permissions.can_manage_finance} />
			</div>
		</div>
	)
}
