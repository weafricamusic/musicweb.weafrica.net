import Link from 'next/link'
import { redirect } from 'next/navigation'

import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { engagementLevel, labelPromotionSurface, labelPromotionType } from '@/lib/admin/promotions'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type PromotionMetricRow = {
	id: string
	title: string | null
	promotion_type: string | null
	surface: string | null
	country: string | null
	status: string | null
	views: number
	clicks: number
}

type TrendingRow = {
	country: string
	total_plays: number
	top_artist: string | null
}

async function safeCount(
	supabase: NonNullable<ReturnType<typeof tryCreateSupabaseAdminClient>>,
	table: string,
	where?: (q: any) => any,
): Promise<number> {
	try {
		let q = supabase.from(table).select('id', { head: true, count: 'exact' })
		if (where) q = where(q)
		const { count } = await q
		return count ?? 0
	} catch {
		return 0
	}
}

export default async function PromotionAnalyticsPage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const country = await getAdminCountryCode()
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for Promotion Analytics" />

	// ── Promotion metrics ───────────────────────────────────────────────────
	let metrics: PromotionMetricRow[] = []
	let metricsError: string | null = null

	const metricsRes = await supabase
		.from('promotion_events')
		.select('promotion_id, event_type')
		.eq('country_code', country)
		.gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString())
		.limit(5000)

	if (metricsRes.data && Array.isArray(metricsRes.data)) {
		// Tally views & clicks per promotion_id
		const tally = new Map<string, { views: number; clicks: number }>()
		for (const row of metricsRes.data as Array<{ promotion_id: string; event_type: string }>) {
			const t = tally.get(row.promotion_id) ?? { views: 0, clicks: 0 }
			if (row.event_type === 'view') t.views += 1
			else if (row.event_type === 'click') t.clicks += 1
			tally.set(row.promotion_id, t)
		}

		if (tally.size > 0) {
			const ids = [...tally.keys()]
			const promoRes = await supabase
				.from('promotions')
				.select('id,title,promotion_type,surface,country,status')
				.in('id', ids)

			if (promoRes.data && Array.isArray(promoRes.data)) {
				metrics = (promoRes.data as Array<Record<string, unknown>>).map((p) => {
					const t = tally.get(String(p.id)) ?? { views: 0, clicks: 0 }
					return {
						id: String(p.id),
						title: p.title != null ? String(p.title) : null,
						promotion_type: p.promotion_type != null ? String(p.promotion_type) : null,
						surface: p.surface != null ? String(p.surface) : null,
						country: p.country != null ? String(p.country) : null,
						status: p.status != null ? String(p.status) : null,
						views: t.views,
						clicks: t.clicks,
					}
				})
				metrics.sort((a, b) => b.views - a.views)
			}
		}
	} else if (metricsRes.error) {
		const msg = String(metricsRes.error.message ?? '')
		if (/promotion_events|schema cache|could not find/i.test(msg)) {
			metricsError = 'promotion_events table not yet created — run the promotion_engine migration.'
		} else {
			metricsError = msg
		}
	}

	// Fallback: show promotions with 0 metrics if events table has no data
	if (metrics.length === 0 && !metricsError) {
		const promoRes = await supabase
			.from('promotions')
			.select('id,title,promotion_type,surface,country,status')
			.eq('is_active', true)
			.order('created_at', { ascending: false })
			.limit(20)
		if (promoRes.data && Array.isArray(promoRes.data)) {
			metrics = (promoRes.data as Array<Record<string, unknown>>).map((p) => ({
				id: String(p.id),
				title: p.title != null ? String(p.title) : null,
				promotion_type: p.promotion_type != null ? String(p.promotion_type) : null,
				surface: p.surface != null ? String(p.surface) : null,
				country: p.country != null ? String(p.country) : null,
				status: p.status != null ? String(p.status) : null,
				views: 0,
				clicks: 0,
			}))
		}
	}

	// ── Trending by country ─────────────────────────────────────────────────
	let trending: TrendingRow[] = []

	// Get top-played artist per country from song_streams (or analytics_events)
	const trendingRes = await supabase
		.from('analytics_events')
		.select('country_code, properties')
		.eq('event_name', 'song_play')
		.gte('created_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
		.limit(5000)

	if (trendingRes.data && Array.isArray(trendingRes.data)) {
		const byCountry = new Map<string, Map<string, number>>()
		for (const row of trendingRes.data as Array<{ country_code: string; properties: Record<string, unknown> | null }>) {
			const cc = String(row.country_code ?? '').toUpperCase()
			if (!cc || cc.length !== 2) continue
			const artistId = String((row.properties ?? {})['artist_id'] ?? (row.properties ?? {})['artist_name'] ?? '')
			if (!artistId) continue
			const countryMap = byCountry.get(cc) ?? new Map<string, number>()
			countryMap.set(artistId, (countryMap.get(artistId) ?? 0) + 1)
			byCountry.set(cc, countryMap)
		}

		for (const [cc, artistMap] of byCountry.entries()) {
			const topEntry = [...artistMap.entries()].sort((a, b) => b[1] - a[1])[0]
			const totalPlays = [...artistMap.values()].reduce((a, b) => a + b, 0)
			trending.push({ country: cc, top_artist: topEntry?.[0] ?? null, total_plays: totalPlays })
		}
		trending.sort((a, b) => b.total_plays - a.total_plays)
	} else {
		// Fallback: show countries active on the platform
		const countriesRes = await supabase
			.from('countries')
			.select('country_code,country_name')
			.eq('is_active', true)
			.order('country_name', { ascending: true })
			.limit(20)
		if (countriesRes.data && Array.isArray(countriesRes.data)) {
			trending = (countriesRes.data as Array<{ country_code: string; country_name: string }>).map((c) => ({
				country: c.country_code,
				top_artist: null,
				total_plays: 0,
			}))
		}
	}

	// ── Summary counts ──────────────────────────────────────────────────────
	const [totalActive, totalPending, totalPaid] = await Promise.all([
		safeCount(supabase, 'promotions', (q) => q.eq('status', 'active')),
		safeCount(supabase, 'paid_promotions', (q) => q.eq('status', 'pending')),
		safeCount(supabase, 'paid_promotions', (q) => q.in('status', ['active', 'approved'])),
	])

	const totalViews = metrics.reduce((a, r) => a + r.views, 0)
	const totalClicks = metrics.reduce((a, r) => a + r.clicks, 0)
	const overallCtr =
		totalViews > 0 ? `${((totalClicks / totalViews) * 100).toFixed(2)}%` : '—'

	const COUNTRY_NAMES: Record<string, string> = {
		MW: 'Malawi', NG: 'Nigeria', ZA: 'South Africa', KE: 'Kenya',
		GH: 'Ghana', TZ: 'Tanzania', UG: 'Uganda', ZW: 'Zimbabwe',
		ZM: 'Zambia', ET: 'Ethiopia', SN: 'Senegal', CI: "Côte d'Ivoire",
	}

	return (
		<div className="space-y-6">
			{/* Header */}
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold text-white">Promotion Analytics</h1>
						<p className="mt-1 text-sm text-gray-400">
							Views, clicks, and engagement for all active promotions. Last 30 days.
						</p>
						<p className="mt-2 text-xs text-gray-500">Scope: {country}</p>
					</div>
					<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back to Ads
					</Link>
				</div>
			</div>

			{metricsError ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					{metricsError}
				</div>
			) : null}

			{/* Summary stats */}
			<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
				{[
					{ label: 'Active Promotions', value: String(totalActive) },
					{ label: 'Pending Paid', value: String(totalPending) },
					{ label: 'Live Paid Promos', value: String(totalPaid) },
					{ label: 'Total Views (30d)', value: totalViews.toLocaleString() },
					{ label: 'Overall CTR', value: overallCtr },
				].map((s) => (
					<div key={s.label} className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">{s.label}</p>
						<p className="mt-1 text-lg font-semibold text-white">{s.value}</p>
					</div>
				))}
			</div>

			{/* Promotion performance table */}
			<div className="rounded-2xl border border-white/10 bg-white/5 overflow-hidden">
				<div className="px-5 py-4 border-b border-white/10">
					<h2 className="text-sm font-semibold text-white">Promotion Performance</h2>
					<p className="text-xs text-gray-400 mt-1">Sorted by views. CTR = clicks ÷ views.</p>
				</div>
				<div className="overflow-x-auto">
					<table className="min-w-[800px] w-full text-sm">
						<thead className="bg-black/20 text-left text-xs text-gray-400">
							<tr>
								<th className="px-4 py-3">Promotion</th>
								<th className="px-4 py-3">Type</th>
								<th className="px-4 py-3">Surface</th>
								<th className="px-4 py-3">Country</th>
								<th className="px-4 py-3 text-right">Views</th>
								<th className="px-4 py-3 text-right">Clicks</th>
								<th className="px-4 py-3">CTR</th>
								<th className="px-4 py-3">Engagement</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10">
							{metrics.length > 0 ? (
								metrics.map((r) => {
									const ctr =
										r.views > 0
											? `${((r.clicks / r.views) * 100).toFixed(2)}%`
											: '—'
									const eng = engagementLevel(r.views, r.clicks)
									const engCls =
										eng === 'High'
											? 'text-emerald-300'
											: eng === 'Medium'
												? 'text-amber-300'
												: 'text-gray-400'
									return (
										<tr key={r.id} className="hover:bg-white/5">
											<td className="px-4 py-3">
												<p className="font-medium text-white">{r.title ?? 'Untitled'}</p>
												<p className="text-xs text-gray-500">{r.id.slice(0, 8)}…</p>
											</td>
											<td className="px-4 py-3 text-gray-200">{labelPromotionType(r.promotion_type)}</td>
											<td className="px-4 py-3 text-gray-200">{labelPromotionSurface(r.surface)}</td>
											<td className="px-4 py-3 text-gray-200">{r.country ?? '—'}</td>
											<td className="px-4 py-3 text-right text-gray-100">{r.views.toLocaleString()}</td>
											<td className="px-4 py-3 text-right text-gray-100">{r.clicks.toLocaleString()}</td>
											<td className="px-4 py-3 text-gray-300">{ctr}</td>
											<td className={`px-4 py-3 font-medium ${engCls}`}>{eng}</td>
										</tr>
									)
								})
							) : (
								<tr>
									<td colSpan={8} className="px-4 py-8 text-center text-sm text-gray-400">
										No promotion data yet. Events will appear as creators and admins run promotions.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>

			{/* Trending by Country */}
			<div className="rounded-2xl border border-white/10 bg-white/5 overflow-hidden">
				<div className="px-5 py-4 border-b border-white/10 flex items-center justify-between">
					<div>
						<h2 className="text-sm font-semibold text-white">🌍 Trending by Country</h2>
						<p className="text-xs text-gray-400 mt-1">
							Top activity per market in the last 7 days — based on song play events.
						</p>
					</div>
					<a
						href="/api/promotions/trending-by-country"
						target="_blank"
						rel="noreferrer"
						className="text-xs text-gray-400 underline hover:text-white"
					>
						API →
					</a>
				</div>
				<div className="divide-y divide-white/10">
					{trending.length > 0 ? (
						trending.slice(0, 12).map((t, i) => (
							<div
								key={t.country}
								className="flex items-center justify-between px-5 py-3 hover:bg-white/5"
							>
								<div className="flex items-center gap-3">
									<span className="text-lg font-bold text-gray-500 w-6 text-right">{i + 1}</span>
									<div>
										<p className="text-sm font-medium text-white">
											Trending {COUNTRY_NAMES[t.country] ?? t.country}
										</p>
										{t.top_artist ? (
											<p className="text-xs text-gray-400">Top artist: {t.top_artist}</p>
										) : null}
									</div>
								</div>
								<div className="text-right">
									<p className="text-sm font-semibold text-amber-300">
										{t.total_plays > 0 ? t.total_plays.toLocaleString() : '—'}
									</p>
									<p className="text-xs text-gray-500">plays</p>
								</div>
							</div>
						))
					) : (
						<div className="px-5 py-8 text-center text-sm text-gray-400">
							No play data available yet. Trending will populate as the app collects analytics events.
						</div>
					)}
				</div>
			</div>

			{/* Promo quick-actions */}
			<div className="grid gap-4 sm:grid-cols-3">
				<Link href="/admin/ads/admin-promotions/new" className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:bg-white/10 transition">
					<p className="text-sm font-semibold text-white">+ Create Promotion</p>
					<p className="mt-1 text-xs text-gray-400">Admin-controlled promotion on any surface</p>
				</Link>
				<Link href="/admin/ads/paid-promotions" className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:bg-white/10 transition">
					<p className="text-sm font-semibold text-white">Review Paid Promotions</p>
					<p className="mt-1 text-xs text-gray-400">Approve or reject creator coin-paid boosts</p>
				</Link>
				<Link href="/admin/ads/surfaces" className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:bg-white/10 transition">
					<p className="text-sm font-semibold text-white">Promotion Surfaces</p>
					<p className="mt-1 text-xs text-gray-400">Home Banner, Discover, Feed, Live Battle, Events</p>
				</Link>
			</div>
		</div>
	)
}
