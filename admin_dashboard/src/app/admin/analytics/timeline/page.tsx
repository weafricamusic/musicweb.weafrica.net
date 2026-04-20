import Link from 'next/link'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type SearchParams = {
	country?: string
	event?: string
	limit?: string
	kind?: string
}

function normalizeLimit(raw: string | undefined): number {
	const n = Number(raw ?? '200')
	if (!Number.isFinite(n)) return 200
	return Math.max(50, Math.min(1000, Math.floor(n)))
}

function normalizeText(raw: string | undefined, max: number): string | null {
	const v = (raw ?? '').trim()
	if (!v) return null
	return v.length > max ? v.slice(0, max) : v
}

function PrettyJson({ value }: { value: unknown }) {
	if (value == null) return <span className="text-gray-500">—</span>
	let pretty: string | null = null
	try {
		pretty = JSON.stringify(value, null, 2)
	} catch {
		pretty = null
	}
	if (pretty != null) {
		return <pre className="whitespace-pre-wrap break-words text-xs text-gray-300">{pretty}</pre>
	}
	return <span className="text-xs text-gray-300">{String(value)}</span>
}

export default async function AnalyticsTimelinePage(props: { searchParams: Promise<SearchParams> }) {
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
	const limit = normalizeLimit(sp.limit)
	const kind = normalizeText(sp.kind, 32) ?? 'analytics'
	const eventFilter = normalizeText(sp.event, 80)

	const cookieCountry = await getAdminCountryCode()
	const countryFilter = normalizeText(sp.country, 8)?.toUpperCase() ?? (cookieCountry ? String(cookieCountry).toUpperCase() : null)

	const exportHref =
		`/api/admin/analytics/timeline/export?kind=${encodeURIComponent(kind)}` +
		(limit ? `&limit=${encodeURIComponent(String(limit))}` : '') +
		(countryFilter ? `&country=${encodeURIComponent(String(countryFilter))}` : '') +
		(eventFilter ? `&event=${encodeURIComponent(String(eventFilter))}` : '')

	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) return <ServiceRoleRequired title="Service role required for timeline" />
	const supabase = supabaseAdmin

	let rows: any[] = []
	let error: string | null = null
	let used: 'analytics_events' | 'admin_logs' = 'analytics_events'

	if (kind === 'admin') {
		used = 'admin_logs'
		try {
			let q = supabase
				.from('admin_logs')
				.select('created_at,action,admin_email,target_type,target_id,reason,meta')
				.order('created_at', { ascending: false })
				.limit(limit)
			if (eventFilter) q = q.ilike('action', `%${eventFilter}%`)
			const { data, error: e } = await q
			if (e) throw e
			rows = (data ?? []) as any[]
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load admin logs'
			rows = []
		}
	} else {
		try {
			let q = supabaseAdmin
				.from('analytics_events')
				.select('created_at,event_name,user_id,actor_type,actor_id,session_id,country_code,stream_id,platform,app_version,source,properties')
				.order('created_at', { ascending: false })
				.limit(limit)
			if (countryFilter) q = q.eq('country_code', countryFilter)
			if (eventFilter) q = q.eq('event_name', eventFilter)
			const { data, error: e } = await q
			if (e) throw e
			rows = (data ?? []) as any[]
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load analytics activity'
			rows = []
		}
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-2xl font-bold">Timeline</h1>
						<p className="mt-1 text-sm text-gray-400">Chronological view of platform activity (telemetry + admin logs).</p>
						<p className="mt-2 text-xs text-gray-500">
							Showing: <b>{used}</b> • Limit: {limit}
							{countryFilter && used === 'analytics_events' ? ` • Country: ${countryFilter}` : ''}
							{eventFilter ? ` • Filter: ${eventFilter}` : ''}
						</p>
					</div>
					<div className="flex gap-2">
						<Link href="/admin/analytics" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Back
						</Link>
						<Link
							href={exportHref}
							prefetch={false}
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Export CSV
						</Link>
						<Link
							href="/admin/analytics/timeline?kind=analytics"
							className={`inline-flex h-10 items-center rounded-xl px-4 text-sm ${used === 'analytics_events' ? 'bg-white/10' : 'border border-white/10 hover:bg-white/5'}`}
						>
							Analytics
						</Link>
						<Link
							href="/admin/analytics/timeline?kind=admin"
							className={`inline-flex h-10 items-center rounded-xl px-4 text-sm ${used === 'admin_logs' ? 'bg-white/10' : 'border border-white/10 hover:bg-white/5'}`}
						>
							Admin Logs
						</Link>
					</div>
				</div>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div>
			) : null}

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<table className="w-full text-sm">
					<thead className="bg-black/20 text-xs text-gray-400">
						<tr>
							<th className="px-4 py-3 text-left">When</th>
							<th className="px-4 py-3 text-left">Event</th>
							<th className="px-4 py-3 text-left">Actor/User</th>
							<th className="px-4 py-3 text-left">Target/Stream</th>
							<th className="px-4 py-3 text-left">Meta</th>
						</tr>
					</thead>
					<tbody className="divide-y divide-white/10">
						{rows.length ? (
							rows.map((r, idx) => (
								<tr key={idx} className="align-top hover:bg-white/5">
									<td className="px-4 py-3 text-xs text-gray-400 whitespace-nowrap">
										{r.created_at ? new Date(String(r.created_at)).toLocaleString() : '—'}
									</td>
									<td className="px-4 py-3">
										<div className="font-medium">
											{used === 'admin_logs' ? String(r.action ?? '—') : String(r.event_name ?? '—')}
										</div>
										{used === 'analytics_events' ? (
											<div className="mt-1 text-xs text-gray-400">
												{[r.platform, r.app_version, r.source, r.country_code].filter(Boolean).join(' • ')}
											</div>
										) : r.reason ? (
											<div className="mt-1 text-xs text-gray-400">Reason: {String(r.reason)}</div>
										) : null}
									</td>
									<td className="px-4 py-3 text-xs text-gray-300">
										{used === 'admin_logs'
											? String(r.admin_email ?? '—')
											: [r.user_id, r.actor_id].filter(Boolean).join(' / ') || '—'}
									</td>
									<td className="px-4 py-3 text-xs text-gray-300">
										{used === 'admin_logs'
											? [r.target_type, r.target_id].filter(Boolean).join(':') || '—'
											: String(r.stream_id ?? '—')}
									</td>
									<td className="px-4 py-3">
										<PrettyJson value={used === 'admin_logs' ? r.meta : r.properties} />
									</td>
								</tr>
							))
						) : (
							<tr>
								<td className="px-4 py-6 text-sm text-gray-400" colSpan={5}>
									No activity found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
