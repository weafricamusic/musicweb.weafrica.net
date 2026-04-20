import Link from 'next/link'
import { getAdminContext } from '@/lib/admin/session'
import { notFound } from 'next/navigation'

export const runtime = 'nodejs'

export default async function EmailNotificationsPage() {
	if (process.env.NODE_ENV === 'production') notFound()

	const ctx = await getAdminContext()
	if (!ctx) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You are not an active admin.</p>
				<div className="mt-4">
					<Link
						href="/admin/dashboard"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Return to dashboard
					</Link>
				</div>
			</div>
		)
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Email</h1>
					<p className="mt-1 text-sm text-gray-400">This section is scaffolded but not implemented yet.</p>
				</div>
				<Link href="/admin/notifications" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<p className="text-sm text-gray-400">Planned: templates, campaigns, opt-outs, and sending provider integration.</p>
			</div>

			<div className="flex flex-wrap gap-2">
				<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to Overview
				</Link>
				<Link href="/admin/health" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					System Health
				</Link>
			</div>
		</div>
	)
}
