'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useState } from 'react'

export type EarningsRow = {
	beneficiaryId: string
	name: string
	livesHosted?: number
	coins: number
	earnedMwk: number
	withdrawnMwk: number
	availableMwk: number
	pendingWithdrawalsMwk: number
	status: 'active' | 'frozen'
}

export function EarningsTable(props: {
	role: 'artist' | 'dj'
	rows: EarningsRow[]
}) {
	const { role, rows } = props
	const router = useRouter()
	const [busyId, setBusyId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [reasonById, setReasonById] = useState<Record<string, string>>({})

	async function setFrozen(id: string, frozen: boolean) {
		if (busyId) return
		setError(null)
		setBusyId(id)
		try {
			const res = await fetch(`/api/admin/finance/earnings/${encodeURIComponent(role)}/${encodeURIComponent(id)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'set_frozen', frozen, reason: reasonById[id] || undefined }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to update earnings status')
			}
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update earnings status')
		} finally {
			setBusyId(null)
		}
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex items-end justify-between">
				<div>
					<h2 className="text-base font-semibold">{role === 'artist' ? 'Artist Earnings' : 'DJ Earnings'}</h2>
					<p className="mt-1 text-sm text-gray-400">Freeze earnings for fraud protection. No deletions.</p>
					{error ? <p className="mt-2 text-sm text-red-400">{error}</p> : null}
				</div>
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Name</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Total Coins Earned</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Equivalent MWK</th>
							{role === 'dj' ? (
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Lives Hosted</th>
							) : null}
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Withdrawn</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Pending</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Available</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Actions</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((r) => {
								const isBusy = busyId === r.beneficiaryId
								return (
									<tr key={r.beneficiaryId}>
										<td className="border-b border-white/10 py-3 pr-4 font-medium">
											<div className="flex items-center gap-2">
												<span className="truncate">{r.name}</span>
												<Link
													href={`/admin/payments/earnings/${role === 'artist' ? 'artists' : 'djs'}/${encodeURIComponent(
														r.beneficiaryId,
													)}`}
													className="text-xs text-gray-400 hover:text-white"
												>
													View
												</Link>
											</div>
										</td>
										<td className="border-b border-white/10 py-3 pr-4">{r.coins.toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{r.earnedMwk.toLocaleString()}</td>
										{role === 'dj' ? (
											<td className="border-b border-white/10 py-3 pr-4">{Number(r.livesHosted ?? 0).toLocaleString()}</td>
										) : null}
										<td className="border-b border-white/10 py-3 pr-4">{r.withdrawnMwk.toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{r.pendingWithdrawalsMwk.toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{r.availableMwk.toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{r.status === 'frozen' ? (
												<span className="rounded-full bg-red-500/10 px-2 py-1 text-xs text-red-300">Frozen</span>
											) : (
												<span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Active</span>
											)}
										</td>
										<td className="border-b border-white/10 py-3 pr-4">
											<div className="flex flex-wrap items-center gap-2">
												<input
													value={reasonById[r.beneficiaryId] ?? ''}
													onChange={(e) =>
														setReasonById((m) => ({ ...m, [r.beneficiaryId]: e.target.value }))
													}
													disabled={isBusy}
													placeholder="Reason (optional)"
													className="h-9 w-44 rounded-xl border border-white/10 bg-black/20 px-3 text-xs outline-none disabled:opacity-60"
												/>
												{r.status === 'frozen' ? (
													<button
														disabled={isBusy}
														onClick={() => setFrozen(r.beneficiaryId, false)}
														className="inline-flex h-9 items-center rounded-xl bg-emerald-600 px-3 text-sm disabled:opacity-60"
													>
														{isBusy ? 'Saving…' : 'Unfreeze'}
													</button>
												) : (
													<button
														disabled={isBusy}
														onClick={() => setFrozen(r.beneficiaryId, true)}
														className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm disabled:opacity-60"
													>
														{isBusy ? 'Saving…' : 'Freeze'}
													</button>
												)}
											</div>
										</td>
									</tr>
								)
							})
						) : (
							<tr>
									<td colSpan={role === 'dj' ? 9 : 8} className="py-6 text-sm text-gray-400">
									No earnings yet.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
