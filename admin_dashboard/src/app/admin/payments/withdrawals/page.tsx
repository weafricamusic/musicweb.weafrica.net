import Link from 'next/link'
import { adminBackendFetchJson } from '@/lib/admin/backend'
import { WithdrawalsTable, type WithdrawalRow } from './WithdrawalsTable'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

export default async function WithdrawalsPage(props: {
	searchParams: Promise<{ status?: string }>
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
	const status = (sp.status ?? 'pending').toLowerCase()

	let rows: WithdrawalRow[] = []
	let errorMessage: string | null = null
	try {
		rows = await adminBackendFetchJson<WithdrawalRow[]>(`/admin/finance/withdrawals${status !== 'all' ? `?status=${encodeURIComponent(status)}` : ''}`)
	} catch (error) {
		errorMessage = error instanceof Error ? error.message : 'Failed to load withdrawals'
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Withdrawals</h1>
					<p className="mt-1 text-sm text-gray-400">Approve manually, pay externally, then mark as paid.</p>
				</div>
				<Link
					href="/admin/payments"
					className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
				>
					Back to overview
				</Link>
			</div>

			{errorMessage ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load withdrawals: {errorMessage}. Check the admin backend and finance schema alignment.
				</div>
			) : null}

			<WithdrawalsTable rows={rows} />
		</div>
	)
}
