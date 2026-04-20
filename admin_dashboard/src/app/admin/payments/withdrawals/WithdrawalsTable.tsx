'use client'

import { useRouter, useSearchParams } from 'next/navigation'
import { useMemo, useState } from 'react'

export type WithdrawalRow = {
	id: string
	beneficiary_type: 'artist' | 'dj' | 'user'
	beneficiary_id: string
	display_name: string
	amount_mwk: number
	method: string
	status: 'pending' | 'approved' | 'paid' | 'rejected'
	requested_at: string
	admin_email: string | null
	note: string | null
}

export function WithdrawalsTable(props: { rows: WithdrawalRow[] }) {
	const { rows } = props
	const router = useRouter()
	const params = useSearchParams()
	const [busyId, setBusyId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)

	const status = params.get('status') ?? 'pending'

	const statusOptions = useMemo(() => ['pending', 'approved', 'paid', 'rejected', 'all'], [])

	function setFilter(nextStatus: string) {
		const sp = new URLSearchParams(params.toString())
		sp.set('status', nextStatus)
		router.push(`/admin/payments/withdrawals?${sp.toString()}`)
	}

	async function update(id: string, action: 'approve' | 'reject' | 'mark_paid') {
		if (busyId != null) return
		setError(null)
		setBusyId(id)
		try {
			const res = await fetch(`/api/admin/finance/withdrawals/${encodeURIComponent(String(id))}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to update withdrawal')
			}
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update withdrawal')
		} finally {
			setBusyId(null)
		}
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
				<div>
					<h2 className="text-base font-semibold">Withdrawals Management</h2>
					<p className="mt-1 text-sm text-gray-400">Manual approval only. Payments happen externally.</p>
					{error ? <p className="mt-2 text-sm text-red-400">{error}</p> : null}
				</div>
				<div>
					<label className="block text-xs text-gray-400">Status</label>
					<select
						value={status}
						onChange={(e) => setFilter(e.target.value)}
						className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm"
					>
						{statusOptions.map((s) => (
							<option key={s} value={s}>
								{s}
							</option>
						))}
					</select>
				</div>
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">User</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Role</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Amount (MWK)</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Method</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Requested</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((w) => {
								const isBusy = busyId === w.id
								return (
									<tr key={w.id}>
										<td className="border-b border-white/10 py-3 pr-4 font-medium">
											<div className="min-w-0">
												<p className="truncate">{w.display_name}</p>
												<p className="truncate text-xs text-gray-500">{w.beneficiary_id}</p>
											</div>
										</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.beneficiary_type.toUpperCase()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.amount_mwk.toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.method}</td>
										<td className="border-b border-white/10 py-3 pr-4">{w.status}</td>
										<td className="border-b border-white/10 py-3 pr-4">{new Date(w.requested_at).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											<div className="flex flex-wrap gap-2">
												{w.status === 'pending' ? (
													<>
														<button
															disabled={isBusy}
															onClick={() => update(w.id, 'approve')}
															className="inline-flex h-9 items-center rounded-xl bg-emerald-600 px-3 text-sm disabled:opacity-60"
														>
															{isBusy ? 'Saving…' : 'Approve'}
														</button>
														<button
															disabled={isBusy}
															onClick={() => update(w.id, 'reject')}
															className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm disabled:opacity-60"
														>
															{isBusy ? 'Saving…' : 'Reject'}
														</button>
													</>
												) : null}
												{w.status === 'approved' ? (
													<button
														disabled={isBusy}
														onClick={() => update(w.id, 'mark_paid')}
														className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 disabled:opacity-60"
													>
														{isBusy ? 'Saving…' : 'Mark Paid'}
													</button>
												) : null}
											</div>
										</td>
									</tr>
								)
							})
						) : (
							<tr>
								<td colSpan={7} className="py-6 text-sm text-gray-400">
									No withdrawals found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
