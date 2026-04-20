import Link from 'next/link'
import { getAdminContext } from '@/lib/admin/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'

export const runtime = 'nodejs'

type FinanceSummary = {
	period?: string
	start_date?: string | null
	total_revenue?: number | null
	total_payouts?: number | null
	platform_fees?: number | null
	net_revenue?: number | null
}

type WithdrawalRow = {
	id?: string | null
	status?: string | null
	amount?: number | string | null
	created_at?: string | null
}

function formatMoneyMwk(value: number | null | undefined): string {
	if (value == null || Number.isNaN(Number(value))) return '—'
	return `MWK ${new Intl.NumberFormat().format(Math.round(Number(value)))}`
}

async function loadFinanceSnapshot() {
	try {
		const [summary, pendingWithdrawals] = await Promise.all([
			adminBackendFetchJson<FinanceSummary>('/admin/finance/summary?period=month'),
			adminBackendFetchJson<WithdrawalRow[]>('/admin/finance/withdrawals?status=pending'),
		])

		const pendingAmount = (Array.isArray(pendingWithdrawals) ? pendingWithdrawals : []).reduce((sum, row) => {
			return sum + Number(row.amount ?? 0)
		}, 0)

		return {
			summary,
			pendingWithdrawals: Array.isArray(pendingWithdrawals) ? pendingWithdrawals.length : 0,
			pendingAmount,
		}
	} catch {
		return {
			summary: null,
			pendingWithdrawals: 0,
			pendingAmount: 0,
		}
	}
	}

function Card(props: { title: string; desc: string; href: string }) {
	return (
		<Link href={props.href} className="rounded-2xl border border-white/10 bg-white/5 p-6 hover:bg-white/10 transition">
			<h2 className="text-base font-semibold">{props.title}</h2>
			<p className="mt-1 text-sm text-gray-400">{props.desc}</p>
			<p className="mt-4 text-xs text-gray-500">Open →</p>
		</Link>
	)
}

export default async function MoneyPage() {
	const ctx = await getAdminContext()
	const canMoney = !!ctx?.permissions.can_manage_finance || ctx?.admin.role === 'super_admin'
	const snapshot = await loadFinanceSnapshot()

	if (!ctx || !canMoney) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Finance Admin only.</p>
				<div className="mt-4">
					<Link
						href="/admin/dashboard"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Return to overview
					</Link>
				</div>
			</div>
		)
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-2xl font-bold">Money</h1>
				<p className="mt-1 text-sm text-gray-400">Sensitive area: strict state transitions and audit logs.</p>
				<p className="mt-3 text-xs text-gray-500">Admin backend snapshot for the current month.</p>
			</div>

			<div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
				<StatCard title="Revenue" value={formatMoneyMwk(snapshot.summary?.total_revenue)} hint="Coin purchases and other tracked inflows" />
				<StatCard title="Payouts" value={formatMoneyMwk(snapshot.summary?.total_payouts)} hint="Approved and paid withdrawals" />
				<StatCard title="Platform Fees" value={formatMoneyMwk(snapshot.summary?.platform_fees)} hint="Current backend fee calculation" />
				<StatCard
					title="Pending Withdrawals"
					value={new Intl.NumberFormat().format(snapshot.pendingWithdrawals)}
					hint={snapshot.pendingWithdrawals ? formatMoneyMwk(snapshot.pendingAmount) : 'No pending requests'}
				/>
			</div>

			<div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
				<Card title="Subscriptions" desc="Plans, rules, payments, and user subscriptions." href="/admin/subscriptions" />
				<Card title="Payments" desc="Transactions, coins, earnings, withdrawals." href="/admin/payments" />
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Scaffolded next</h2>
				<p className="mt-1 text-sm text-gray-400">These routes exist in navigation and will be implemented as dedicated pages.</p>
				<div className="mt-4 flex flex-wrap gap-2">
					<Link href="/admin/payments/withdrawals?status=paid" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Payouts</Link>
					<Link href="/admin/countries" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Pricing &amp; Currency</Link>
					<Link href="/admin/payments/earnings/artists" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Royalties</Link>
				</div>
			</div>
		</div>
	)
}

function StatCard(props: { title: string; value: string; hint: string }) {
	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<p className="text-xs text-gray-400">{props.title}</p>
			<p className="mt-2 text-2xl font-semibold">{props.value}</p>
			<p className="mt-2 text-xs text-gray-500">{props.hint}</p>
		</div>
	)
}
