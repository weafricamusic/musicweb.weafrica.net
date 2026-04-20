import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { reasonLabel } from '../_types'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type ReportRow = {
	id: number
	content_id: string
	reason: string
	created_at: string
	status: string
}

type StreamRow = {
	id: number
	channel_name: string
	status: string
	viewer_count: number
	host_type: string
	host_id: string | null
}

export default async function LiveViolationsPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for live violations" />
	const { data: reports, error } = await supabase
		.from('reports')
		.select('id,content_id,reason,created_at,status')
		.eq('content_type', 'live')
		.eq('status', 'open')
		.order('created_at', { ascending: false })
		.limit(200)

	const rows = (reports ?? []) as ReportRow[]
	const streamIds = Array.from(new Set(rows.map((r) => r.content_id).filter(Boolean)))

	let streamsById = new Map<string, StreamRow>()
	try {
		if (streamIds.length) {
			const { data } = await supabase
				.from('live_streams')
				.select('id,channel_name,status,viewer_count,host_type,host_id')
				.in('id', streamIds)
			const streams = (data ?? []) as any[]
			streamsById = new Map(streams.map((s) => [String(s.id), s as StreamRow]))
		}
	} catch {
		streamsById = new Map()
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Live Stream Violations</h1>
						<p className="mt-1 text-sm text-gray-400">Highest priority queue. Stop streams instantly when needed.</p>
					</div>
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
				{error ? <p className="mt-4 text-sm text-red-400">Failed to load live reports: {error.message}</p> : null}
			</div>

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<table className="w-full text-sm">
					<thead className="bg-black/20 text-xs text-gray-400">
						<tr>
							<th className="px-4 py-3 text-left">Report</th>
							<th className="px-4 py-3 text-left">Stream</th>
							<th className="px-4 py-3 text-left">Reason</th>
							<th className="px-4 py-3 text-left">Viewers</th>
							<th className="px-4 py-3 text-left">Date</th>
							<th className="px-4 py-3 text-right">Action</th>
						</tr>
					</thead>
					<tbody className="divide-y divide-white/10">
						{rows.length ? (
							rows.map((r) => {
								const s = streamsById.get(String(r.content_id))
								return (
									<tr key={r.id} className="hover:bg-white/5">
										<td className="px-4 py-3">#{r.id}</td>
										<td className="px-4 py-3">
											<p className="font-medium">{s ? s.channel_name : String(r.content_id)}</p>
											<p className="mt-1 text-xs text-gray-400">{s ? `${s.host_type} ${s.host_id ?? ''}` : '—'}</p>
										</td>
										<td className="px-4 py-3">{reasonLabel(r.reason)}</td>
										<td className="px-4 py-3">{s ? String(s.viewer_count ?? 0) : '—'}</td>
										<td className="px-4 py-3">{new Date(r.created_at).toLocaleString()}</td>
										<td className="px-4 py-3 text-right">
											<div className="flex justify-end gap-2">
												{s ? (
													<Link href={`/admin/live-streams/${String(s.id)}`} className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">
														Monitor
													</Link>
												) : null}
												<Link href={`/admin/moderation/reports/${r.id}`} className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">
													Review
												</Link>
											</div>
										</td>
									</tr>
								)
							})
						) : (
							<tr>
								<td className="px-4 py-6 text-sm text-gray-400" colSpan={6}>
									No open live reports.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
