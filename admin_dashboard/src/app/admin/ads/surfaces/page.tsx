import Link from 'next/link'
import { redirect } from 'next/navigation'

import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

const SURFACES = [
	{
		id: 'home_banner',
		label: 'Home Banner',
		emoji: '🔥',
		description: 'Top of the app — highest visibility. Shows trending artists, battles, and events.',
		examples: ['Trending Artist of the Week', 'Upcoming Battle', 'Festival Announcement'],
		placement: 'Full-width banner above the home feed',
		recommended: 'Artist & Event promotions',
	},
	{
		id: 'discover',
		label: 'Discover Page',
		emoji: '🔍',
		description: 'Discovery carousels — surfaces trending DJs, top artists, and popular battles.',
		examples: ['Trending DJs in Malawi', 'Top Artists Nigeria', 'Popular Battles This Week'],
		placement: 'Horizontal scrollable cards in the Discover section',
		recommended: 'DJ & Artist promotions',
	},
	{
		id: 'feed',
		label: 'Video Feed',
		emoji: '🎬',
		description: 'Between-video placements in the video scroll feed, TikTok-style.',
		examples: ['Sponsored Artist', 'Promoted Battle', 'WeAfrica Ride ad'],
		placement: 'Inserted every N videos in the feed',
		recommended: 'Paid creator promotions & Ride',
	},
	{
		id: 'live_battle',
		label: 'Live Battle Page',
		emoji: '⚔️',
		description: 'Featured battle callout shown before entering a live battle session.',
		examples: ['🔥 Featured Battle Tonight', 'Challenge accepted — watch live'],
		placement: 'Banner above the live battle list',
		recommended: 'Battle promotions',
	},
	{
		id: 'events',
		label: 'Events Section',
		emoji: '🎪',
		description: 'Highlighted upcoming concerts, festivals, and WeAfrica-organised events.',
		examples: ['Upcoming Concerts', 'Festival in Blantyre', 'Online Battle Event'],
		placement: 'Featured card at top of Events list',
		recommended: 'Event & Ride promotions',
	},
]

export default async function PromotionSurfacesPage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const isOps = ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin'

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold text-white">Promotion Surfaces</h1>
						<p className="mt-1 text-sm text-gray-400">
							Where promotions appear inside the WeAfrica app. Choose the right surface when creating admin or paid promotions.
						</p>
					</div>
					<div className="flex gap-2">
						<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Back to Ads
						</Link>
						{isOps ? (
							<Link
								href="/admin/ads/admin-promotions/new"
								className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90"
							>
								+ Create Promotion
							</Link>
						) : null}
					</div>
				</div>
			</div>

			<div className="grid gap-5 lg:grid-cols-2">
				{SURFACES.map((s) => (
					<div key={s.id} className="rounded-2xl border border-white/10 bg-white/5 p-5 space-y-3">
						<div className="flex items-center gap-3">
							<span className="text-2xl">{s.emoji}</span>
							<div>
								<h2 className="text-base font-semibold text-white">{s.label}</h2>
								<code className="text-xs text-gray-500">{s.id}</code>
							</div>
						</div>
						<p className="text-sm text-gray-300">{s.description}</p>
						<div className="space-y-2 text-sm">
							<div>
								<span className="text-xs text-gray-500 uppercase tracking-wider">Placement</span>
								<p className="text-gray-200">{s.placement}</p>
							</div>
							<div>
								<span className="text-xs text-gray-500 uppercase tracking-wider">Best for</span>
								<p className="text-emerald-300">{s.recommended}</p>
							</div>
							<div>
								<span className="text-xs text-gray-500 uppercase tracking-wider">Examples</span>
								<ul className="mt-1 space-y-1">
									{s.examples.map((ex) => (
										<li key={ex} className="text-gray-400">• {ex}</li>
									))}
								</ul>
							</div>
						</div>
						{isOps ? (
							<Link
								href={`/admin/ads/admin-promotions/new?surface=${s.id}`}
								className="inline-flex h-9 items-center rounded-xl border border-white/10 px-4 text-xs hover:bg-white/10"
							>
								Create {s.label} promotion →
							</Link>
						) : null}
					</div>
				))}
			</div>

			{/* Surface → API mapping */}
			<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
				<h2 className="text-sm font-semibold text-white">Consumer API Integration</h2>
				<p className="mt-2 text-sm text-gray-400">
					The consumer / mobile app fetches active promotions per surface using the public promotions endpoint:
				</p>
				<pre className="mt-3 overflow-x-auto rounded-xl bg-black/40 px-4 py-3 text-xs text-gray-300">
{`GET /api/promotions?surface=home_banner&country_code=MW
GET /api/promotions?surface=discover&country_code=NG
GET /api/promotions?surface=feed&country_code=ZA`}
				</pre>
				<p className="mt-3 text-sm text-gray-400">
					Response shape: <code className="text-xs bg-black/30 px-1 rounded">{'{ ok: true, data: Promotion[] }'}</code> — only{' '}
					<span className="text-emerald-300">active</span> promotions within their schedule window are returned.
				</p>
			</div>
		</div>
	)
}
