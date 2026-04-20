import Link from 'next/link'

import { adminBackendFetchJson } from '@/lib/admin/backend'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'
import { formatInt, formatMWK } from '@/app/admin/payments/_format'

export const runtime = 'nodejs'

type AnalyticsPayload = {
	range: { days: number; startIso: string }
	country: string | null
	revenueSeriesMwk: Array<{ day: string; value: number }> | null
	coinsSoldSeries: Array<{ day: string; value: number }> | null
	newUsersSeries: Array<{ day: string; value: number }> | null
	newSongsSeries: Array<{ day: string; value: number }> | null
	newVideosSeries: Array<{ day: string; value: number }> | null
	streamsStartedSeries: Array<{ day: string; value: number }> | null
	revenueMwk: number | null
	revenueByTypeMwk: Record<string, number> | null
	coinsSold: number | null
	pendingWithdrawalsMwk: number | null
	pendingWithdrawalsCount: number | null
	newUsers: number | null
	newSongs: number | null
	newVideos: number | null
	dau1d: number | null
	mau30d: number | null
	stickiness: number | null
	openReports: number | null
	frozenEarningsAccounts: number | null
	activeStreams: number | null
	avgViewersRecent: number | null
	maxViewersRecent: number | null
	streamJoinAttempts: number | null
	streamJoinSuccesses: number | null
	streamJoinSuccessRate: number | null
	warnings: string[]
}

function StatCard(props: { title: string; value: string; hint?: string; href?: string }) {
	const inner = (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:bg-white/10 transition">
			<p className="text-xs text-gray-400">{props.title}</p>
			<p className="mt-2 text-2xl font-semibold">{props.value}</p>
			{props.hint ? <p className="mt-2 text-xs text-gray-500">{props.hint}</p> : null}
		</div>
	)
	return props.href ? (
		<Link href={props.href} className="block">
			{inner}
		</Link>
	) : (
		inner
	)
}

function MiniBars(props: { title: string; series: Array<{ day: string; value: number }> | null; format?: (n: number) => string }) {
	const s = props.series ?? []
	if (!s.length) {
		return (
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h3 className="text-sm font-semibold">{props.title}</h3>
				<p className="mt-2 text-sm text-gray-400">No time-series data available.</p>
			</div>
		)
	}
	const max = Math.max(1, ...s.map((x) => x.value))
	const fmt = props.format ?? ((n: number) => String(Math.round(n)))
	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<h3 className="text-sm font-semibold">{props.title}</h3>
			<div className="mt-4 grid gap-2">
				{s.slice(-14).map((p) => (
					<div key={p.day} className="grid grid-cols-[90px_1fr_90px] items-center gap-3 text-xs">
						<div className="text-gray-500">{p.day}</div>
						<div className="h-2 rounded-full bg-black/30 overflow-hidden">
							<div
								className="h-2 rounded-full bg-white/30"
								style={{ width: `${Math.max(2, Math.round((p.value / max) * 100))}%` }}
							/>
						</div>
						<div className="text-right text-gray-300">{fmt(p.value)}</div>
					</div>
				))}
			</div>
		</div>
	)
}

export default async function AnalyticsPage(props: { searchParams: Promise<{ days?: string }> }) {
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

	const sp = await props.searchParams
	const days = Math.max(1, Math.min(90, Number(sp.days ?? '7') || 7))

	const country = await getAdminCountryCode()
	const intel = await adminBackendFetchJson<AnalyticsPayload>(
		`/admin/analytics?days=${encodeURIComponent(String(days))}${country ? `&country=${encodeURIComponent(country)}` : ''}`,
	)

	const revenueLabel = intel.revenueMwk == null ? '—' : formatMWK(intel.revenueMwk)
	const coinsLabel = intel.coinsSold == null ? '—' : formatInt(intel.coinsSold)
	const pendingWLabel = intel.pendingWithdrawalsMwk == null ? '—' : formatMWK(intel.pendingWithdrawalsMwk)
	const pendingCLabel = intel.pendingWithdrawalsCount == null ? '—' : formatInt(intel.pendingWithdrawalsCount)

	const usersLabel = intel.newUsers == null ? '—' : formatInt(intel.newUsers)
	const songsLabel = intel.newSongs == null ? '—' : formatInt(intel.newSongs)
	const videosLabel = intel.newVideos == null ? '—' : formatInt(intel.newVideos)

	const reportsLabel = intel.openReports == null ? '—' : formatInt(intel.openReports)
	const frozenLabel = intel.frozenEarningsAccounts == null ? '—' : formatInt(intel.frozenEarningsAccounts)

	const activeStreamsLabel = intel.activeStreams == null ? '—' : formatInt(intel.activeStreams)
	const avgViewersLabel = intel.avgViewersRecent == null ? '—' : formatInt(Math.round(intel.avgViewersRecent))
	const maxViewersLabel = intel.maxViewersRecent == null ? '—' : formatInt(Math.round(intel.maxViewersRecent))

	const dauLabel = intel.dau1d == null ? '—' : formatInt(intel.dau1d)
	const mauLabel = intel.mau30d == null ? '—' : formatInt(intel.mau30d)
	const stickinessLabel =
		intel.stickiness == null ? '—' : `${Math.round(Math.max(0, Math.min(1, intel.stickiness)) * 100)}%`
	const joinRateLabel =
		intel.streamJoinSuccessRate == null
			? '—'
			: `${Math.round(Math.max(0, Math.min(1, intel.streamJoinSuccessRate)) * 100)}%`

	const exportHref = `/api/admin/analytics/export?days=${encodeURIComponent(String(days))}${country ? `&country=${encodeURIComponent(String(country))}` : ''}`

	return (
		<div className="space-y-8">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-2xl font-bold">Platform Intelligence</h1>
						<p className="mt-1 text-sm text-gray-400">
							Revenue, user behavior, content performance, fraud risk, and streaming quality — in one place.
						</p>
						<p className="mt-2 text-xs text-gray-500">
							Range: last {intel.range.days} days{country ? ` • Country: ${country}` : ''}
						</p>
					</div>
					<div className="flex gap-2">
						<Link
							href="/admin/dashboard"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Dashboard
						</Link>
						<Link
							href={exportHref}
							prefetch={false}
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Export CSV
						</Link>
						<Link
							href="/admin/analytics/reports"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Reports
						</Link>
						<Link
							href="/admin/analytics/flags"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Flags
						</Link>
						<Link
							href="/admin/analytics/flags/saved"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Saved flags
						</Link>
						<Link
							href="/admin/analytics/timeline"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Timeline
						</Link>
						<Link
							href={`/admin/analytics?days=${encodeURIComponent(String(days === 7 ? 30 : 7))}`}
							className="inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15"
						>
							Toggle {days === 7 ? '30d' : '7d'}
						</Link>
					</div>
				</div>
			</div>

			<section className="space-y-4">
				<div className="flex items-end justify-between">
					<div>
						<h2 className="text-base font-semibold">Monetization</h2>
						<p className="mt-1 text-sm text-gray-400">What the platform is earning and how.</p>
					</div>
					<Link href="/admin/payments" className="text-sm underline text-gray-200 hover:text-white">
						Finance overview
					</Link>
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
					<StatCard title="Revenue (MWK)" value={revenueLabel} hint={`Last ${intel.range.days} days`} href="/admin/payments/transactions?type=revenue" />
					<StatCard title="Coins Sold" value={coinsLabel} hint={`Last ${intel.range.days} days`} href="/admin/payments/transactions?type=coin_purchase" />
					<StatCard title="Pending Withdrawals" value={pendingCLabel} hint={pendingWLabel} href="/admin/payments/withdrawals?status=pending" />
					<StatCard title="Revenue Mix" value={intel.revenueByTypeMwk ? 'View' : '—'} hint="Coin purchase / subscription / ads" href="#revenue-mix" />
				</div>

				<div className="grid gap-4 md:grid-cols-2">
					<MiniBars title="Revenue trend (MWK/day)" series={intel.revenueSeriesMwk} format={(n) => formatMWK(n)} />
					<MiniBars title="Coins sold trend (coins/day)" series={intel.coinsSoldSeries} format={(n) => formatInt(n)} />
				</div>

				<div id="revenue-mix" className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h3 className="text-sm font-semibold">Revenue mix (MWK)</h3>
					<p className="mt-1 text-xs text-gray-500">Simple breakdown from recent transactions (not a full BI cube yet).</p>
					{intel.revenueByTypeMwk ? (
						<div className="mt-4 grid gap-3 md:grid-cols-3">
							{Object.entries(intel.revenueByTypeMwk).map(([k, v]) => (
								<div key={k} className="rounded-xl border border-white/10 bg-black/20 p-4">
									<p className="text-xs text-gray-400">{k}</p>
									<p className="mt-1 text-lg font-semibold">{formatMWK(v)}</p>
								</div>
							))}
						</div>
					) : (
						<p className="mt-3 text-sm text-gray-400">Not available (table/RLS not accessible).</p>
					)}
				</div>
			</section>

			<section className="space-y-4">
				<div>
					<h2 className="text-base font-semibold">Users & Content</h2>
					<p className="mt-1 text-sm text-gray-400">Supply-side and demand-side growth indicators.</p>
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-3">
					<StatCard title="New Users" value={usersLabel} hint={`Last ${intel.range.days} days (Supabase users table)`} />
					<StatCard title="New Songs" value={songsLabel} hint={`Last ${intel.range.days} days`} href="/dashboard/artists" />
					<StatCard title="New Videos" value={videosLabel} hint={`Last ${intel.range.days} days`} href="/dashboard/artists" />
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-3">
					<StatCard title="DAU" value={dauLabel} hint="Distinct users with app_open (last 24h)" />
					<StatCard title="MAU" value={mauLabel} hint="Distinct users with app_open (last 30d)" />
					<StatCard title="Stickiness" value={stickinessLabel} hint="DAU / MAU" />
				</div>

				<div className="grid gap-4 md:grid-cols-3">
					<MiniBars title="New users/day" series={intel.newUsersSeries} format={(n) => formatInt(n)} />
					<MiniBars title="New songs/day" series={intel.newSongsSeries} format={(n) => formatInt(n)} />
					<MiniBars title="New videos/day" series={intel.newVideosSeries} format={(n) => formatInt(n)} />
				</div>
			</section>

			<section className="space-y-4">
				<div className="flex items-end justify-between">
					<div>
						<h2 className="text-base font-semibold">Fraud & Risk</h2>
						<p className="mt-1 text-sm text-gray-400">Signals for abuse, chargeback risk, and payout safety.</p>
					</div>
					<Link href="/admin/moderation" className="text-sm underline text-gray-200 hover:text-white">
						Moderation
					</Link>
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-3">
					<StatCard title="Open Reports" value={reportsLabel} hint="Backlog to clear" href="/admin/moderation/reports?status=open" />
					<StatCard title="Frozen Earnings" value={frozenLabel} hint="Accounts flagged/frozen" href="/admin/payments/earnings/artists" />
					<StatCard title="Pending Withdrawals (MWK)" value={pendingWLabel} hint="Risk exposure" href="/admin/payments/withdrawals?status=pending" />
				</div>
			</section>

			<section className="space-y-4">
				<div className="flex items-end justify-between">
					<div>
						<h2 className="text-base font-semibold">Streaming Quality</h2>
						<p className="mt-1 text-sm text-gray-400">Availability and engagement. RTC QoS needs additional telemetry.</p>
					</div>
					<Link href="/admin/live-streams" className="text-sm underline text-gray-200 hover:text-white">
						Live streams
					</Link>
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-3">
					<StatCard title="Active Streams" value={activeStreamsLabel} hint="Status = live" href="/admin/live-streams?status=live" />
					<StatCard title="Avg Viewers" value={avgViewersLabel} hint={`Streams started in last ${intel.range.days} days`} />
					<StatCard title="Max Viewers" value={maxViewersLabel} hint={`Streams started in last ${intel.range.days} days`} />
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-3">
					<StatCard title="Stream Join Success" value={joinRateLabel} hint={`Telemetry (last ${intel.range.days} days)`} />
					<StatCard title="Join Attempts" value={intel.streamJoinAttempts == null ? '—' : formatInt(intel.streamJoinAttempts)} />
					<StatCard title="Join Successes" value={intel.streamJoinSuccesses == null ? '—' : formatInt(intel.streamJoinSuccesses)} />
				</div>
				<MiniBars title="Streams started/day" series={intel.streamsStartedSeries} format={(n) => formatInt(n)} />
			</section>

			{intel.warnings.length ? (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h3 className="text-sm font-semibold">Data availability</h3>
					<p className="mt-1 text-xs text-gray-500">
						Some metrics are best-effort until all analytics tables/telemetry are wired.
					</p>
					<ul className="mt-3 space-y-1 text-sm text-gray-400 list-disc pl-5">
						{intel.warnings.map((w, i) => (
							<li key={i}>{w}</li>
						))}
					</ul>
				</div>
			) : null}
		</div>
	)
}
