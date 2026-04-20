import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type Row = {
	id: number
	report_id: number | null
	admin_email: string | null
	action: string
	reason: string | null
	target_type: string | null
	target_id: string | null
	created_at: string
}

export default async function ModerationLogsPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for moderation logs" />
	const { data, error } = await supabase
		.from('moderation_actions')
		.select('id,report_id,admin_email,action,reason,target_type,target_id,created_at')
		.order('created_at', { ascending: false })
		.limit(250)

	const rows = (data ?? []) as Row[]

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Moderation Action Logs</h1>
						<p className="mt-1 text-sm text-gray-400">Every moderation decision is recorded (legal shield).</p>
					</div>
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
				{error ? <p className="mt-4 text-sm text-red-400">Failed to load logs: {error.message}</p> : null}
			</div>

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<table className="w-full text-sm">
					<thead className="bg-black/20 text-xs text-gray-400">
						<tr>
							<th className="px-4 py-3 text-left">When</th>
							<th className="px-4 py-3 text-left">Admin</th>
							<th className="px-4 py-3 text-left">Action</th>
							<th className="px-4 py-3 text-left">Reason</th>
							<th className="px-4 py-3 text-left">Target</th>
							<th className="px-4 py-3 text-right">Report</th>
						</tr>
					</thead>
					<tbody className="divide-y divide-white/10">
						{rows.length ? (
							rows.map((r) => (
								<tr key={r.id} className="hover:bg-white/5">
									<td className="px-4 py-3">{new Date(r.created_at).toLocaleString()}</td>
									<td className="px-4 py-3">{r.admin_email ?? '—'}</td>
									<td className="px-4 py-3 font-medium">{r.action}</td>
									<td className="px-4 py-3">{r.reason ?? '—'}</td>
									<td className="px-4 py-3">{r.target_type ? `${r.target_type}:${r.target_id ?? ''}` : '—'}</td>
									<td className="px-4 py-3 text-right">
										{r.report_id ? (
											<Link href={`/admin/moderation/reports/${r.report_id}`} className="text-xs underline">
												#{r.report_id}
											</Link>
										) : (
											'—'
										)}
									</td>
								</tr>
							))
						) : (
							<tr>
								<td className="px-4 py-6 text-sm text-gray-400" colSpan={6}>
									No moderation actions yet.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
