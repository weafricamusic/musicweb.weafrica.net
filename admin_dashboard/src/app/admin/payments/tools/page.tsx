import Link from 'next/link'
import FinanceToolsClient from './FinanceToolsClient'

export const runtime = 'nodejs'

export default function FinanceToolsPage() {
	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Finance Tools</h1>
					<p className="mt-1 text-sm text-gray-400">Create real ledger entries to validate dashboards end-to-end.</p>
				</div>
				<Link
					href="/admin/payments"
					className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
				>
					Back to overview
				</Link>
			</div>

			<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
				<b>Note:</b> This page never deletes financial records. It only inserts new rows.
			</div>

			<FinanceToolsClient />
		</div>
	)
}
