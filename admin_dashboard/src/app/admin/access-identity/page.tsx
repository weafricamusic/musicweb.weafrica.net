import Link from 'next/link'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

function Card(props: { title: string; desc: string; href: string }) {
	return (
		<Link href={props.href} className="rounded-2xl border border-white/10 bg-white/5 p-6 hover:bg-white/10 transition">
			<h2 className="text-base font-semibold">{props.title}</h2>
			<p className="mt-1 text-sm text-gray-400">{props.desc}</p>
			<p className="mt-4 text-xs text-gray-500">Open →</p>
		</Link>
	)
}

export default async function AccessIdentityPage() {
	const ctx = await getAdminContext()
	const canIdentity =
		!!ctx?.permissions.can_manage_users ||
		!!ctx?.permissions.can_manage_artists ||
		!!ctx?.permissions.can_manage_djs ||
		ctx?.admin.role === 'super_admin'

	if (!ctx || !canIdentity) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Identity + trust tools only.</p>
				<div className="mt-4">
					<Link
						href="/admin/dashboard"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Return to overview
					</Link>
				</div>
			</div>
		)
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-2xl font-bold">Access &amp; Identity</h1>
				<p className="mt-1 text-sm text-gray-400">Who can do what. No payments. No content moderation.</p>
			</div>

			<div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
				<Card title="Users — Consumers" desc="Search and review consumer accounts." href="/admin/users" />
				<Card title="Users — Artists" desc="Artist profiles, status, and permissions." href="/admin/artists" />
				<Card title="Users — DJs" desc="DJ profiles, status, and permissions." href="/admin/djs" />
				<Card title="Admin Users" desc="Create/suspend admins and set roles. Super Admin only." href="/admin/settings" />
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Verification (scaffolded)</h2>
				<p className="mt-1 text-sm text-gray-400">These routes exist in navigation and will be implemented next.</p>
				<div className="mt-4 flex flex-wrap gap-2">
					<Link href="/admin/verification/artists/pending" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Artist — Pending
					</Link>
					<Link href="/admin/verification/djs/pending" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						DJ — Pending
					</Link>
				</div>
			</div>
		</div>
	)
}
