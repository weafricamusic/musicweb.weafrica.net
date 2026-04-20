import Link from 'next/link'

import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'

export const runtime = 'nodejs'

export default async function AnalyticsReportsPage(props: { searchParams: Promise<{ days?: string; country?: string }> }) {
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
	const cookieCountry = await getAdminCountryCode().catch(() => null)
	const country = (sp.country ?? '').trim().toUpperCase() || (cookieCountry ? String(cookieCountry).toUpperCase() : '')

	const exportCsvHref = `/api/admin/analytics/export?days=${encodeURIComponent(String(days))}${country ? `&country=${encodeURIComponent(country)}` : ''}`
	const reportHref = `/api/admin/analytics/report?days=${encodeURIComponent(String(days))}${country ? `&country=${encodeURIComponent(country)}` : ''}`

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-2xl font-bold">Reports</h1>
						<p className="mt-1 text-sm text-gray-400">Export analytics for sharing, finance reviews, or weekly ops meetings.</p>
						<p className="mt-2 text-xs text-gray-500">
							Range: last {days} days{country ? ` • Country: ${country}` : ''}
						</p>
					</div>
					<div className="flex gap-2">
						<Link
							href="/admin/analytics"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Back
						</Link>
						<Link
							href={exportCsvHref}
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
							prefetch={false}
						>
							Download CSV
						</Link>
						<Link
							href={reportHref}
							className="inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15"
							prefetch={false}
						>
							Download HTML report
						</Link>
					</div>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Tips</h2>
				<ul className="mt-2 space-y-2 text-sm text-gray-300">
					<li>HTML report is printable (browser “Print” → “Save as PDF”).</li>
					<li>CSV export includes both summary metrics and per-day series in one file (sectioned rows).</li>
					<li>Open risk flags are included only if <code>SUPABASE_SERVICE_ROLE_KEY</code> is configured.</li>
				</ul>
			</div>
		</div>
	)
}
