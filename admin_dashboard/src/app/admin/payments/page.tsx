import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { formatInt, formatMWK } from './_format'
import { getAdminContext } from '@/lib/admin/session'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type FinanceTopSummary = {
	total_revenue_mwk: string | number
	coins_sold: string | number
	artist_earnings_mwk: string | number
	dj_earnings_mwk: string | number
	weafrica_commission_mwk: string | number
	pending_withdrawals_mwk: string | number
	commission_percent: string | number
	artist_share_percent: string | number
	dj_share_percent: string | number
}

function Card(props: { title: string; value: string; href: string }) {
	return (
		<Link
			href={props.href}
			className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:bg-white/10 transition"
		>
			<p className="text-xs text-gray-400">{props.title}</p>
			<p className="mt-2 text-xl font-semibold">{props.value}</p>
			<p className="mt-2 text-xs text-gray-500">View details →</p>
		</Link>
	)
}

export default async function PaymentsPage() {
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
	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) return <ServiceRoleRequired title="Service role required for finance" />
	const supabase = supabaseAdmin

	const { data: summaryRows } = await supabase.rpc('finance_top_summary')
	const summary = (Array.isArray(summaryRows) ? summaryRows[0] : null) as FinanceTopSummary | null

	const { data: coins } = await supabase
		.from('coins')
		.select('id,code,name,value_mwk,status')
		.order('value_mwk', { ascending: true })
		.limit(50)

	const totalRevenue = formatMWK(summary?.total_revenue_mwk)
	const coinsSold = formatInt(summary?.coins_sold)
	const artistEarnings = formatMWK(summary?.artist_earnings_mwk)
	const djEarnings = formatMWK(summary?.dj_earnings_mwk)
	const commission = formatMWK(summary?.weafrica_commission_mwk)
	const pendingWithdrawals = formatMWK(summary?.pending_withdrawals_mwk)

	const commissionPct = summary?.commission_percent ?? '—'
	const artistPct = summary?.artist_share_percent ?? '—'
	const djPct = summary?.dj_share_percent ?? '—'

	return (
		<div className="space-y-8">


			<div className="sticky top-0 z-10 -mx-6 px-6 py-4 bg-[#0e1117]/95 backdrop-blur border-b border-white/10">
				<div className="flex items-end justify-between">
					<div>
						<h1 className="text-2xl font-bold">Finance Overview</h1>
						<p className="mt-1 text-sm text-gray-400">All values are in MWK. No auto payouts.</p>
					</div>
					<div className="flex gap-2">
						<Link
							href="/admin/payments/tools"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Finance tools
						</Link>
						<Link
							href="/admin/payments/withdrawals?status=pending"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Review withdrawals
						</Link>
						<Link
							href="/admin/payments/transactions"
							className="inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15"
						>
							View transactions
						</Link>
					</div>
				</div>

				<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
					<Card title="Total Revenue" value={totalRevenue} href="/admin/payments/transactions?type=revenue" />
					<Card title="Coins Sold" value={coinsSold} href="/admin/payments/transactions?type=coin_purchase" />
					<Card title="Artist Earnings" value={artistEarnings} href="/admin/payments/earnings/artists" />
					<Card title="DJ Earnings" value={djEarnings} href="/admin/payments/earnings/djs" />
					<Card title="WeAfrica Commission" value={commission} href="/admin/payments/commission" />
					<Card title="Pending Withdrawals" value={pendingWithdrawals} href="/admin/payments/withdrawals?status=pending" />
				</div>
			</div>

			<section className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-center justify-between">
					<div>
						<h2 className="text-base font-semibold">Coins System Overview</h2>
						<p className="mt-1 text-sm text-gray-400">
							User buys coins → uses coins → DJ/Artist earns → admin approves withdrawal.
						</p>
					</div>
					<Link
						href="/admin/payments/coins"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Manage coins
					</Link>
				</div>

				<div className="mt-4 overflow-auto">
					<table className="w-full min-w-[720px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Coin</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Value (MWK)</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Used For</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							</tr>
						</thead>
						<tbody>
							{coins?.length ? (
								coins.map((c) => (
									<tr key={c.id}>
										<td className="border-b border-white/10 py-3 pr-4 font-medium">{c.name}</td>
										<td className="border-b border-white/10 py-3 pr-4">{formatMWK(c.value_mwk as any)}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{String(c.code).toLowerCase() === 'diamond'
												? 'Premium'
												: String(c.code).toLowerCase() === 'gold'
													? 'Battles'
													: 'Gifts'}
										</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{c.status === 'active' ? (
												<span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">
													Active
												</span>
											) : (
												<span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Disabled</span>
											)}
										</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={4} className="py-6 text-sm text-gray-400">
										No coin types found. Apply the finance migration in Supabase.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</section>

			<section className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Commission & Settings (read-only)</h2>
				<p className="mt-1 text-sm text-gray-400">Editable later when the platform stabilizes.</p>
				<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">WeAfrica Commission</p>
						<p className="mt-1 text-lg font-semibold">{commissionPct}%</p>
					</div>
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">Artist Share</p>
						<p className="mt-1 text-lg font-semibold">{artistPct}%</p>
					</div>
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">DJ Share</p>
						<p className="mt-1 text-lg font-semibold">{djPct}%</p>
					</div>
				</div>
				<div className="mt-4">
					<Link
						href="/admin/payments/logs"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						View admin finance logs
					</Link>
				</div>
			</section>
		</div>
	)
}
