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

export default async function VerificationHomePage() {
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
				<p className="mt-2 text-sm text-gray-400">Verification is an identity + trust tool.</p>
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
				<h1 className="text-2xl font-bold">Verification</h1>
				<p className="mt-1 text-sm text-gray-400">Approve or reject creator onboarding. No payments.</p>
			</div>

			<div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
				<Card title="Artists — Pending" desc="Creators awaiting review." href="/admin/verification/artists/pending" />
				<Card title="Artists — Approved" desc="Active creators." href="/admin/verification/artists/approved" />
				<Card title="Artists — Rejected" desc="Blocked creators." href="/admin/verification/artists/rejected" />
				<Card title="DJs — Pending" desc="DJs awaiting review." href="/admin/verification/djs/pending" />
				<Card title="DJs — Approved" desc="Active DJs." href="/admin/verification/djs/approved" />
				<Card title="DJs — Rejected" desc="Blocked DJs." href="/admin/verification/djs/rejected" />
			</div>
		</div>
	)
}
