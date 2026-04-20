import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

export default async function ArtistEarningsDetailPage(props: { params: Promise<{ id: string }> }) {
	const { id } = await props.params
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for earnings" />

	const { data: artist } = await supabase.from('artists').select('id,name,stage_name').eq('id', id).maybeSingle()

	const { data: freeze } = await supabase
		.from('earnings_freeze_state')
		.select('frozen,reason,updated_at,updated_by_email')
		.eq('beneficiary_type', 'artist')
		.eq('beneficiary_id', id)
		.maybeSingle()

	const { data: tx } = await supabase
		.from('transactions')
		.select('id,type,amount_mwk,coins,created_at,source,actor_id')
		.eq('target_type', 'artist')
		.eq('target_id', id)
		.order('created_at', { ascending: false })
		.limit(200)

	const { data: withdrawals } = await supabase
		.from('withdrawals')
		.select('id,amount_mwk,method,status,requested_at,admin_email')
		.eq('beneficiary_type', 'artist')
		.eq('beneficiary_id', id)
		.order('requested_at', { ascending: false })
		.limit(200)

	const title = (artist as any)?.stage_name || (artist as any)?.name || `Artist ${id}`

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">{title}</h1>
					<p className="mt-1 text-sm text-gray-400">Earnings details (transactions + withdrawals).</p>
				</div>
				<Link
					href="/admin/payments/earnings/artists"
					className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
				>
					Back to artists
				</Link>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Status</h2>
				<p className="mt-1 text-sm text-gray-400">
					{(freeze as any)?.frozen ? 'Frozen' : 'Active'}
					{(freeze as any)?.reason ? ` — ${(freeze as any).reason}` : ''}
				</p>
				{(freeze as any)?.updated_at ? (
					<p className="mt-2 text-xs text-gray-500">
						Updated {new Date((freeze as any).updated_at).toLocaleString()} by {(freeze as any).updated_by_email ?? '—'}
					</p>
				) : null}
				<p className="mt-3 text-xs text-gray-500">Use the Freeze/Unfreeze action on the main Artist Earnings page.</p>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Recent Earnings Transactions</h2>
				<div className="mt-4 overflow-auto">
					<table className="w-full min-w-[900px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Type</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Amount (MWK)</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Coins</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Sender</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Source</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Date</th>
							</tr>
						</thead>
						<tbody>
							{(tx ?? []).length ? (
								(tx ?? []).map((t: any) => (
									<tr key={t.id}>
										<td className="border-b border-white/10 py-3 pr-4">{t.type}</td>
										<td className="border-b border-white/10 py-3 pr-4">{Number(t.amount_mwk ?? 0).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{Number(t.coins ?? 0).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{t.actor_id ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">{t.source ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">{new Date(t.created_at).toLocaleString()}</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={6} className="py-6 text-sm text-gray-400">
										No earnings transactions.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Withdrawals</h2>
				<div className="mt-4 overflow-auto">
					<table className="w-full min-w-[900px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Amount (MWK)</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Method</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Requested</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Admin</th>
							</tr>
						</thead>
						<tbody>
							{(withdrawals ?? []).length ? (
								(withdrawals ?? []).map((w: any) => (
									<tr key={w.id}>
										<td className="border-b border-white/10 py-3 pr-4">{Number(w.amount_mwk ?? 0).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.method}</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.status}</td>
										<td className="border-b border-white/10 py-3 pr-4">{new Date(w.requested_at).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.admin_email ?? '—'}</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={5} className="py-6 text-sm text-gray-400">
										No withdrawals.
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
