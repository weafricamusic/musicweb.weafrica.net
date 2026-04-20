import Link from 'next/link'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

function Card(props: { title: string; desc: string; href: string }) {
	return (
		<Link
			href={props.href}
			className="rounded-2xl border border-white/10 bg-white/5 p-6 transition hover:bg-white/10"
		>
			<h3 className="text-base font-semibold">{props.title}</h3>
			<p className="mt-2 text-sm text-gray-400">{props.desc}</p>
		</Link>
	)
}

export default async function InAppNotificationsPage() {
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
					<h1 className="text-2xl font-bold">In-App Notifications</h1>
					<p className="mt-1 text-sm text-gray-400">Manage messages that appear inside the app.</p>
				</div>
				<Link href="/admin/notifications" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Currently supported</h2>
				<p className="mt-2 text-sm text-gray-400">
					In-app announcements are currently powered by the <span className="text-gray-200">Subscription Promotions</span> tool (targets Free/Premium/Platinum or All).
				</p>
				<div className="mt-4 grid gap-4 md:grid-cols-2">
					<Card
						title="Subscription Promotions"
						desc="Create upgrade nudges and VIP announcements (stored in subscription_promotions)."
						href="/admin/subscriptions/promotions"
					/>
					<Card
						title="Content Access Rules"
						desc="Control what content each plan can access (subscription_content_access)."
						href="/admin/subscriptions/content-access"
					/>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Planned</h2>
				<p className="mt-2 text-sm text-gray-400">Next step is user-targeted notifications (segments, deep links, scheduling). This route is now live, but those features aren’t built yet.</p>
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
