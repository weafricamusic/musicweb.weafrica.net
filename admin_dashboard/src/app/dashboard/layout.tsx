import { redirect } from 'next/navigation'
import { Sidebar } from '@/components/Sidebar'
import { Topbar } from '@/components/Topbar'
import { LogoutButton } from '@/components/LogoutButton'
import { BootstrapAdminButton } from '@/components/BootstrapAdminButton'
import { getAdminContext } from '@/lib/admin/session'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'

export const runtime = 'nodejs'

function getSidebarItems(canManageFinance: boolean) {
	return [
		{ href: '/dashboard', label: 'Overview' },
		{ href: '/admin/announcements', label: 'Announcements' },
		{ href: '/dashboard/users', label: 'Users' },
		{ href: '/dashboard/artists', label: 'Artists' },
		{ href: '/dashboard/djs', label: 'DJs' },
		{ href: '/dashboard/live', label: 'Live' },
		...(canManageFinance ? [{ href: '/dashboard/finance', label: 'Finance' }] : []),
		{ href: '/dashboard/moderation', label: 'Moderation' },
	]
}

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
	const ctx = await getAdminContext()
	if (!ctx) {
		// If the user is signed in (Firebase session cookie is valid) but we cannot
		// load the admin row/permissions from Supabase, redirecting back to login
		// is confusing (it looks like login "doesn't work"). Instead, show a clear
		// setup message.
		const firebase = await verifyFirebaseSessionCookie()
		if (!firebase) redirect('/auth/login')

		const rawServiceRole = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim().replace(/^['"]|['"]$/g, '')
		const missingServiceRole =
			!rawServiceRole || rawServiceRole.includes('...') || rawServiceRole.toLowerCase().includes('yourservicerolekey')

		return (
			<div className="min-h-screen bg-zinc-50 px-6 py-10 text-zinc-900 dark:bg-black dark:text-white">
				<div className="mx-auto w-full max-w-2xl rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<div className="flex items-center justify-between gap-4">
						<h1 className="text-xl font-semibold">Dashboard setup required</h1>
						<LogoutButton />
					</div>
					<p className="mt-3 text-sm text-zinc-700 dark:text-zinc-300">
						You&apos;re signed in as <span className="font-medium">{firebase.email ?? firebase.uid}</span>, but the server
						 couldn&apos;t load your admin profile/permissions from Supabase.
					</p>
					<p className="mt-2 text-xs text-zinc-600 dark:text-zinc-400">
						Firebase UID: <span className="font-mono">{firebase.uid}</span>
					</p>

					<div className="mt-5 space-y-3 text-sm">
						{missingServiceRole ? (
							<div className="rounded-xl border border-amber-500/30 bg-amber-50 p-4 text-amber-900 dark:bg-amber-500/10 dark:text-amber-200">
								<div className="font-medium">Missing SUPABASE_SERVICE_ROLE_KEY</div>
								<div className="mt-1">
									Set <code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">SUPABASE_SERVICE_ROLE_KEY</code> in
									 <code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">.env.local</code> and restart <code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">npm run dev</code>.
									 <span className="ml-1 text-xs text-zinc-600 dark:text-zinc-400">Tip: macOS helper (repo root): <code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">npm run admin:setup:supabase -- --service-from-clipboard</code></span>
								</div>
							</div>
						) : (
							<div className="rounded-xl border border-emerald-500/30 bg-emerald-50 p-4 text-emerald-900 dark:bg-emerald-500/10 dark:text-emerald-200">
								<div className="font-medium">Supabase admin access is configured</div>
								<div className="mt-1">Click below to seed your admin record automatically.</div>
								<BootstrapAdminButton />
							</div>
						)}

						<div className="rounded-xl border border-black/[.08] bg-zinc-50 p-4 text-zinc-800 dark:border-white/[.145] dark:bg-white/[.06] dark:text-zinc-200">
							<div className="font-medium">Also verify your admin record</div>
							<div className="mt-1">
								Make sure this email exists in Supabase <code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">admins</code> /{' '}
								<code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">admins_with_permissions</code> and has <code className="rounded bg-black/[.06] px-1 py-0.5 dark:bg-white/[.12]">status=active</code>.
							</div>
						</div>
					</div>
				</div>
			</div>
		)
	}

	return (
		<div className="min-h-screen bg-zinc-50 text-zinc-900 dark:bg-black dark:text-white">
			<div className="mx-auto flex max-w-7xl flex-col md:flex-row">
				<Sidebar items={getSidebarItems(!!ctx.permissions.can_manage_finance)} />
				<div className="min-w-0 flex-1">
					<Topbar userEmail={ctx.admin.email ?? ctx.firebase.uid} />
					<main className="p-6">{children}</main>
				</div>
			</div>
		</div>
	)
}
