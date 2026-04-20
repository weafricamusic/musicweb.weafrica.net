import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'
import { backendReportStatus, contentTypeLabel, reasonLabel, reportStatusLabel } from '../_types'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type ReportRow = {
	id: string
	target_type: string
	target_id: string
	reason: string
	reporter_id: string | null
	description: string | null
	status: string
	created_at: string
	reviewed_at?: string | null
}

export default async function ReportsPage({
	searchParams,
}: {
	searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const sp = await searchParams
	const status = String(sp.status ?? 'open')
	const backendStatus = backendReportStatus(status)

	let rows: ReportRow[] = []
	let errorMessage: string | null = null
	try {
		rows = await adminBackendFetchJson<ReportRow[]>(
			`/admin/reports?limit=250${backendStatus ? `&status=${encodeURIComponent(backendStatus)}` : ''}`,
		)
	} catch (error) {
		errorMessage = error instanceof Error ? error.message : 'Failed to load reports'
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Reported Content Queue</h1>
						<p className="mt-1 text-sm text-gray-400">Review reports and take action without deleting history.</p>
					</div>
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>

				{errorMessage ? <p className="mt-4 text-sm text-red-400">Failed to load reports: {errorMessage}</p> : null}

				<div className="mt-4 flex flex-wrap gap-2 text-sm">
					<Link className={`rounded-xl border px-3 py-1 ${status === 'open' ? 'border-white/20 bg-white/10' : 'border-white/10 hover:bg-white/5'}`} href="/admin/moderation/reports?status=open">
						Open
					</Link>
					<Link className={`rounded-xl border px-3 py-1 ${status === 'resolved' ? 'border-white/20 bg-white/10' : 'border-white/10 hover:bg-white/5'}`} href="/admin/moderation/reports?status=resolved">
						Resolved
					</Link>
					<Link className={`rounded-xl border px-3 py-1 ${status === 'dismissed' ? 'border-white/20 bg-white/10' : 'border-white/10 hover:bg-white/5'}`} href="/admin/moderation/reports?status=dismissed">
						Dismissed
					</Link>
				</div>
			</div>

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<table className="w-full text-sm">
					<thead className="bg-black/20 text-xs text-gray-400">
						<tr>
							<th className="px-4 py-3 text-left">Content</th>
							<th className="px-4 py-3 text-left">Type</th>
							<th className="px-4 py-3 text-left">Report Reason</th>
							<th className="px-4 py-3 text-left">Reported By</th>
							<th className="px-4 py-3 text-left">Date</th>
							<th className="px-4 py-3 text-left">Status</th>
							<th className="px-4 py-3 text-right">Action</th>
						</tr>
					</thead>
					<tbody className="divide-y divide-white/10">
						{rows.length ? (
							rows.map((r) => (
								<tr key={r.id} className="hover:bg-white/5">
									<td className="px-4 py-3">
										<p className="font-medium">{String(r.target_id)}</p>
										{r.description ? <p className="mt-1 line-clamp-2 text-xs text-gray-400">{r.description}</p> : null}
									</td>
									<td className="px-4 py-3">{contentTypeLabel(r.target_type)}</td>
									<td className="px-4 py-3">{reasonLabel(r.reason)}</td>
									<td className="px-4 py-3">{r.reporter_id ? String(r.reporter_id) : '—'}</td>
									<td className="px-4 py-3">{new Date(r.created_at).toLocaleString()}</td>
									<td className="px-4 py-3">
										<span className="rounded-full border border-white/10 bg-black/20 px-2 py-1 text-xs">{reportStatusLabel(r.status)}</span>
									</td>
									<td className="px-4 py-3 text-right">
										<Link href={`/admin/moderation/reports/${r.id}`} className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">
											Review
										</Link>
									</td>
								</tr>
							))
						) : (
							<tr>
								<td className="px-4 py-6 text-sm text-gray-400" colSpan={7}>
									No reports found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
