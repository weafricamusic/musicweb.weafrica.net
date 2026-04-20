import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { getAdminContext } from '@/lib/admin/session'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

export default async function TransactionsPage(props: {
	searchParams: Promise<{ type?: string }>
}) {
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
	const sp = await props.searchParams
	const type = (sp.type ?? 'all').toLowerCase()
	const country = await getAdminCountryCode()

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for transactions" />
	let q = supabase
		.from('transactions')
		.select('id,type,actor_type,actor_id,target_type,target_id,amount_mwk,coins,source,created_at')
		.order('created_at', { ascending: false })
		.limit(500)

	if (country) q = q.eq('country_code', country)

	if (type !== 'all') {
		if (type === 'revenue') q = q.in('type', ['coin_purchase', 'subscription', 'ad'])
		else q = q.eq('type', type)
	}

	const { data, error } = await q

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Transactions</h1>
					<p className="mt-1 text-sm text-gray-400">Ledger of purchases, gifts, battles, and adjustments.</p>
				</div>
				<Link href="/admin/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to overview
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load transactions: {error.message}. Apply finance migration in Supabase.
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="mt-2 overflow-auto">
					<table className="w-full min-w-[1100px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Type</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">User</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Amount (MWK)</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Coins</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Date</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Source</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Recipient</th>
							</tr>
						</thead>
						<tbody>
							{(data ?? []).length ? (
								(data ?? []).map((t: any) => (
									<tr key={t.id}>
										<td className="border-b border-white/10 py-3 pr-4">{t.type}</td>
										<td className="border-b border-white/10 py-3 pr-4">{t.actor_id ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">{Number(t.amount_mwk ?? 0).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{Number(t.coins ?? 0).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{new Date(t.created_at).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{t.source ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{t.target_type ? `${t.target_type}:${t.target_id}` : '—'}
										</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={7} className="py-6 text-sm text-gray-400">
										No transactions found.
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
