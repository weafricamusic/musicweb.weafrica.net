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

export default async function GrowthPage() {
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
				<h1 className="text-2xl font-bold">Growth</h1>
				<p className="mt-1 text-sm text-gray-400">Scheduling + configuration. Avoid destructive actions.</p>
			</div>

			<div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
				<Card title="Featured Artists" desc="Promote artists in discovery surfaces (scaffolded)." href="/admin/growth/featured-artists" />
				<Card title="Featured DJs" desc="Promote DJs in discovery surfaces (scaffolded)." href="/admin/growth/featured-djs" />
				<Card title="Featured Content" desc="Promote tracks/videos/playlists (scaffolded)." href="/admin/growth/featured-content" />
				<Card title="Campaigns" desc="Ads & promotions campaigns." href="/admin/ads/campaigns" />
				<Card title="Ads (AdMob)" desc="AdMob config and rules. Ops-only for now." href="/admin/ads" />
				<Card title="Notifications" desc="Push, in-app, email (scaffolded)." href="/admin/notifications/push" />
			</div>
		</div>
	)
}
