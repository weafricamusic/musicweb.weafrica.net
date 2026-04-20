import Link from 'next/link'
import { redirect } from 'next/navigation'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function normalizeSubscriptionAlias(slug: string[]): string | null {
	const first = String(slug[0] ?? '').trim().toLowerCase()
	if (!['subscription', 'subscriptions', 'subcription', 'subcriptions'].includes(first)) return null

	const second = String(slug[1] ?? '').trim().toLowerCase()
	if (!second) return '/admin/subscriptions'
	if (second === 'artist' || second === 'artists') return '/admin/subscriptions/artists'
	if (second === 'dj' || second === 'djs') return '/admin/subscriptions/djs'
	if (second === 'consumer' || second === 'consumers') {
		const bucket = String(slug[2] ?? 'active').trim().toLowerCase() || 'active'
		const normalizedBucket = ['active', 'past-due', 'cancelled', 'expired'].includes(bucket) ? bucket : 'active'
		return `/admin/subscriptions/consumers/${normalizedBucket}`
	}
	if (second === 'payment' || second === 'payments') return '/admin/subscriptions/payments'
	if (second === 'plan' || second === 'plans') return '/admin/subscriptions/plans'
	if (second === 'promotion' || second === 'promotions') return '/admin/subscriptions/promotions'
	if (second === 'content-access') return '/admin/subscriptions/content-access'
	if (second === 'user-subscription' || second === 'user-subscriptions') return '/admin/subscriptions/user-subscriptions'

	return '/admin/subscriptions'
}

function normalizeAdminAlias(slug: string[]): string | null {
	const first = String(slug[0] ?? '').trim().toLowerCase()
	const second = String(slug[1] ?? '').trim().toLowerCase()
	const third = String(slug[2] ?? '').trim().toLowerCase()
	const fourth = String(slug[3] ?? '').trim().toLowerCase()

	if (first === 'account-actions') return '/admin/access-identity'

	// Common section roots / bookmarks.
	if (first === 'tracks' || first === 'songs') return '/admin/tracks/live'
	if (first === 'videos') return '/admin/videos/live'
	if (first === 'live') return '/admin/live-streams'
	if (first === 'battles') return '/admin/live-battles'
	if (first === 'system' || first === 'risk') return '/admin/system-risk'

	// Legacy / bookmarked content routes.
	if (first === 'content') {
		if (!second) return '/admin/content'
		if (second === 'tracks' || second === 'songs') {
			if (!third || third === 'all' || third === 'live') return '/admin/tracks/live'
			if (third === 'pending' || third === 'pending-approval') return '/admin/tracks/pending'
			if (third === 'removed' || third === 'taken-down') return '/admin/tracks/removed'
			if (third === 'upload' || third === 'new') return '/admin/tracks/upload'
			return '/admin/tracks/live'
		}
		if (second === 'videos') {
			if (!third || third === 'all' || third === 'live') return '/admin/videos/live'
			if (third === 'pending' || third === 'pending-review') return '/admin/videos/pending'
			if (third === 'taken-down' || third === 'removed') return '/admin/videos/taken-down'
			return '/admin/videos/live'
		}
		if (second === 'flags') return '/admin/moderation/flags'
		if (second === 'reports') return '/admin/moderation/reports'
		if (second === 'promotions') {
			if (!third) return '/admin/content/promotions'
			if (third === 'new') return '/admin/content/promotions/new'
			if (third) return `/admin/content/promotions/${encodeURIComponent(third)}`
		}
		if (second === 'moderation') {
			if (!third) return '/admin/moderation'
			if (third === 'users') return '/admin/moderation/users'
			if (third === 'lives') return '/admin/moderation/lives'
			if (third === 'rules') return '/admin/moderation/rules'
			return '/admin/moderation'
		}
		if (second === 'reels') {
			// Not implemented yet; keep user in the closest existing place.
			return '/admin/moderation'
		}
		if (second === 'comments') {
			return '/admin/moderation'
		}
		// e.g. /admin/content/tracks/live/anything...
		if ((second === 'tracks' || second === 'songs') && fourth) return '/admin/tracks/live'
		if (second === 'videos' && fourth) return '/admin/videos/live'
	}

	if (first === 'coins' && second === 'balances') return '/admin/payments/coins'
	if (first === 'royalties') return '/admin/payments'
	if (first === 'payouts') {
		const status = ['pending', 'approved', 'processing', 'paid', 'failed'].includes(second) ? second : 'pending'
		return `/admin/payments/withdrawals?status=${encodeURIComponent(status)}`
	}
	if (first === 'pricing-currency') return '/admin/countries'
	if (first === 'moderation' && (second === 'action' || second === 'actions')) return '/admin/moderation'
	if (first === 'live' && (second === 'scheduled' || second === 'ended')) return '/admin/live-streams'
	if (first === 'live' && second === 'moderation') return '/admin/moderation/lives'
	if (first === 'battles' && ['scheduled', 'live', 'completed'].includes(second)) return '/admin/live-battles'
	if (first === 'battles' && second === 'rules') return '/admin/live-battles'
	if (first === 'growth' && second === 'promotions' && !third) return '/admin/growth/promotions/campaigns'
	if (first === 'growth' && second === 'promotions' && third === 'boosts') return '/admin/growth/promotions/campaigns'
	if (first === 'analytics' && ['users', 'artists', 'djs', 'content'].includes(second)) return '/admin/analytics'
	if (first === 'features' || first === 'security' || first === 'backups') return '/admin/system-risk'

	return null
}

export default async function AdminComingSoonPage(props: { params: Promise<{ slug: string[] }> }) {
	const { slug } = await props.params
	const subscriptionAlias = normalizeSubscriptionAlias(slug)
	if (subscriptionAlias) redirect(subscriptionAlias)
	const adminAlias = normalizeAdminAlias(slug)
	if (adminAlias) redirect(adminAlias)
	const path = `/admin/${slug.map((s) => encodeURIComponent(s)).join('/')}`

	return (
		<div className="mx-auto max-w-2xl space-y-4">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-xl font-semibold">Not available</h1>
				<p className="mt-2 text-sm text-gray-400">
					This admin section is not available in this build.
				</p>
				<div className="mt-3 rounded-xl border border-white/10 bg-black/20 p-3 text-sm">
					<div className="text-gray-400">Route</div>
					<div className="mt-1 font-mono text-gray-200">{path}</div>
				</div>
				<div className="mt-5 flex flex-wrap gap-2">
					<Link
						href="/admin/dashboard"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Back to Overview
					</Link>
					<Link
						href="/admin/health"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						System Health
					</Link>
				</div>
			</div>
		</div>
	)
}
