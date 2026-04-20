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

export default async function LiveBattlesPage() {
	const ctx = await getAdminContext()
	if (!ctx) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You are not an active admin.</p>
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
				<h1 className="text-2xl font-bold">Live &amp; Battles</h1>
				<p className="mt-1 text-sm text-gray-400">Real-time controls. Emergency actions must be logged.</p>
			</div>

			<div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
				<Card title="Live Sessions" desc="Ongoing live streams and controls." href="/admin/live-streams" />
				<Card title="Live Reports" desc="Reports related to live streams." href="/admin/moderation/lives" />
				<Card title="Battles" desc="Scheduled, live, and completed battle operations." href="/admin/live-battles#battle-operations" />
				<Card title="Battle Rules" desc="Duration, scoring, and coin rules overview." href="/admin/live-battles#battle-rules" />
			</div>

			<div id="battle-operations" className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Battle operations</h2>
				<p className="mt-1 text-sm text-gray-400">
					Battle scheduling and live-state control currently run through the live operations workflow and moderation tools.
				</p>
				<div className="mt-4 flex flex-wrap gap-2">
					<Link href="/admin/live-streams" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Open live operations
					</Link>
					<Link href="/admin/moderation/lives" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Open live moderation
					</Link>
				</div>
			</div>

			<div id="battle-rules" className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Battle rules</h2>
				<p className="mt-1 text-sm text-gray-400">
					Rule enforcement is currently managed operationally rather than from a dedicated battle-rules editor.
				</p>
				<ul className="mt-4 space-y-2 text-sm text-gray-300">
					<li>• Duration: enforce session length from live operations.</li>
					<li>• Scoring: review outcome and disputes through moderation and admin logs.</li>
					<li>• Coin rules: reconcile battle-related spend from payments and transaction history.</li>
				</ul>
				<div className="mt-4 flex flex-wrap gap-2">
					<Link href="/admin/payments/transactions?type=battle" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Battle transactions
					</Link>
					<Link href="/admin/logs" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Admin logs
					</Link>
				</div>
			</div>
		</div>
	)
}
