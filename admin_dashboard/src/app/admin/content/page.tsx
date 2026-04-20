import Link from 'next/link'

export const runtime = 'nodejs'

function Card({ title, desc, href }: { title: string; desc: string; href: string }) {
	return (
		<Link href={href} className="rounded-2xl border border-white/10 bg-white/5 p-6 hover:bg-white/10 transition">
			<div className="text-base font-semibold">{title}</div>
			<div className="mt-1 text-sm text-gray-400">{desc}</div>
		</Link>
	)
}

export default function ContentPage() {
	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-2xl font-bold">Content</h1>
				<p className="mt-1 text-sm text-gray-400">Manage creators, approvals, and moderation queues.</p>
			</div>

			<div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
				<Card title="Tracks" desc="View and manage uploaded tracks." href="/admin/tracks/live" />
				<Card title="Videos" desc="View and manage uploaded videos." href="/admin/videos/live" />
				<Card title="Artists" desc="Approve/disable artists and review uploads." href="/admin/artists" />
				<Card title="DJs" desc="Approve/disable DJs and manage profiles." href="/admin/djs" />
				<Card title="Events & Tickets" desc="Create events and sell tickets." href="/admin/events" />
				<Card title="Moderation Reports" desc="Review user reports and actions." href="/admin/moderation/reports" />
				<Card title="Content Flags" desc="Review and resolve content flags." href="/admin/moderation/flags" />
				<Card title="Moderation Rules" desc="Tune safety & enforcement rules." href="/admin/moderation/rules" />
				<Card title="Live Streams" desc="See live streams and stop abuse quickly." href="/admin/live-streams" />
				<Card title="Analytics Reports" desc="Download CSV/HTML reports." href="/admin/analytics/reports" />
			</div>
		</div>
	)
}
