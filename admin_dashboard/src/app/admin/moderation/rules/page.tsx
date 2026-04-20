import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'

export const runtime = 'nodejs'

export default async function SafetyRulesPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Safety Rules (Read-only)</h1>
						<p className="mt-1 text-sm text-gray-400">Guidelines are displayed here to prevent admin abuse.</p>
					</div>
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
			</div>

			<div className="grid gap-6 lg:grid-cols-2">
				<section className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Community Guidelines</h2>
					<ul className="mt-3 space-y-2 text-sm text-gray-300">
						<li>No hate speech, violence incitement, or harassment.</li>
						<li>No nudity/sexual content involving minors. Immediate ban.</li>
						<li>No scams, fraud, or impersonation.</li>
						<li>No spam or repetitive promotional abuse.</li>
					</ul>
				</section>

				<section className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Copyright Policy</h2>
					<ul className="mt-3 space-y-2 text-sm text-gray-300">
						<li>Remove/disable pirated content (soft-disable; never delete records).</li>
						<li>Repeat infringement escalates to account restriction/blocking.</li>
						<li>All admin actions must be logged for legal defense.</li>
					</ul>
				</section>

				<section className="rounded-2xl border border-white/10 bg-white/5 p-6 lg:col-span-2">
					<h2 className="text-base font-semibold">Live Streaming Rules</h2>
					<ul className="mt-3 space-y-2 text-sm text-gray-300">
						<li>Live violations are highest priority; streams can be ended instantly.</li>
						<li>Hosts can be blocked immediately when there is severe violation.</li>
						<li>No nudity/sexual content, hate/violence, or harassment.</li>
						<li>All interventions must be confirmed and logged.</li>
					</ul>
				</section>
			</div>
		</div>
	)
}
