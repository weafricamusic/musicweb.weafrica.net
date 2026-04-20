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

export default async function NotificationsHomePage() {
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
					<h1 className="text-2xl font-bold">Notifications</h1>
					<p className="mt-1 text-sm text-gray-400">Push, in-app, and email messaging surfaces.</p>
				</div>
				<Link href="/admin/growth" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to Growth
				</Link>
			</div>

			<div className="grid gap-4 md:grid-cols-3">
				<Card title="In-App" desc="Announcements and upgrade nudges shown inside the app." href="/admin/notifications/in-app" />
				<Card title="Push" desc="Device push notifications (scaffolded)." href="/admin/notifications/push" />
				{process.env.NODE_ENV === 'production' ? null : (
					<Card title="Email" desc="Email campaigns and transactional templates (scaffolded)." href="/admin/notifications/email" />
				)}
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
