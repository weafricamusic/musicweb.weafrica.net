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

export default async function SystemRiskPage() {
	const ctx = await getAdminContext()
	const isSuper = ctx?.admin.role === 'super_admin'

	if (!ctx || !isSuper) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">System &amp; Risk is Super Admin only.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Return to overview
					</Link>
				</div>
			</div>
		)
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-2xl font-bold">System &amp; Risk</h1>
				<p className="mt-1 text-sm text-gray-400">Platform settings, feature toggles, security, audit, compliance.</p>
			</div>

			<div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
				<Card title="Platform Settings" desc="Admin roles and platform configuration." href="/admin/settings" />
				<Card title="System Health" desc="Live overview of auth, live, payments, and DB." href="/admin/health" />
				<Card title="Audit Logs" desc="Admin logs and finance logs." href="/admin/logs" />
				<Card title="Risk Flags" desc="Automated risk detection and saved flags." href="/admin/analytics/flags" />
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Scaffolded next</h2>
				<p className="mt-1 text-sm text-gray-400">Feature toggles & security controls are scaffolded in navigation.</p>
				<div className="mt-4 flex flex-wrap gap-2">
					<Link href="/admin/settings" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Feature Toggles</Link>
					<Link href="/admin/logs" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Security</Link>
					<Link href="/admin/health" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Backups</Link>
				</div>
			</div>
		</div>
	)
}
