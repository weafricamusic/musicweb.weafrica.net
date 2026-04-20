import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminContext } from '@/lib/admin/session'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

export default async function FinanceLogsPage() {
	const ctx = await getAdminContext()
	if (!ctx || !ctx.permissions.can_manage_finance) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You do not have finance permissions.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for finance logs" />

	const { data, error } = await supabase
		.from('admin_logs')
		.select('id,admin_email,action,target_type,target_id,meta,created_at')
		.ilike('action', 'finance.%')
		.order('created_at', { ascending: false })
		.limit(500)

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Admin Finance Logs</h1>
					<p className="mt-1 text-sm text-gray-400">Every finance action is logged for audit.</p>
				</div>
				<Link href="/admin/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to overview
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load logs: {error.message}
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="overflow-auto">
					<table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Admin</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Target</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Meta</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Time</th>
							</tr>
						</thead>
						<tbody>
							{(data ?? []).length ? (
								(data ?? []).map((l: any) => (
									<tr key={l.id}>
										<td className="border-b border-white/10 py-3 pr-4">{l.admin_email ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">{l.action}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{l.target_type}:{l.target_id}
										</td>
										<td className="border-b border-white/10 py-3 pr-4">
											<pre className="max-w-[420px] overflow-auto whitespace-pre-wrap text-xs text-gray-300">
												{JSON.stringify(l.meta ?? {}, null, 2)}
											</pre>
										</td>
										<td className="border-b border-white/10 py-3 pr-4">{new Date(l.created_at).toLocaleString()}</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={5} className="py-6 text-sm text-gray-400">
										No finance logs yet.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>
		</div>
	)
}
