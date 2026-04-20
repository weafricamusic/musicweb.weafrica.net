'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { ConfirmDialog } from '@/components/ConfirmDialog'

export type CoinRow = {
	id: number
	code: string
	name: string
	value_mwk: number
	status: 'active' | 'disabled'
}

export function CoinsTable(props: { coins: CoinRow[] }) {
	const { coins } = props
	const router = useRouter()
	const [busyId, setBusyId] = useState<number | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirmOpen, setConfirmOpen] = useState(false)
	const [pending, setPending] = useState<{ id: number; status: 'active' | 'disabled'; name: string } | null>(null)

	async function setStatus(id: number, status: 'active' | 'disabled', reason?: string) {
		if (busyId != null) return
		setError(null)
		setBusyId(id)
		try {
			const res = await fetch(`/api/admin/finance/coins/${encodeURIComponent(String(id))}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'set_status', status, reason: reason ?? '' }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to update coin')
			}
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update coin')
		} finally {
			setBusyId(null)
		}
	}

	function requestChange(c: CoinRow, status: 'active' | 'disabled') {
		setPending({ id: c.id, status, name: c.name })
		setConfirmOpen(true)
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<ConfirmDialog
				open={confirmOpen}
				title={pending?.status === 'disabled' ? 'Disable coin type?' : 'Enable coin type?'}
				description={
					pending
						? `This will ${pending.status === 'disabled' ? 'disable' : 'enable'} “${pending.name}”. No deletions are performed.`
						: undefined
				}
				confirmText={pending?.status === 'disabled' ? 'Disable' : 'Enable'}
				confirmTone={pending?.status === 'disabled' ? 'danger' : 'primary'}
				busy={pending?.id != null && busyId === pending.id}
				onCancelAction={() => {
					setConfirmOpen(false)
					setPending(null)
				}}
				onConfirmAction={({ reason }) => {
					if (!pending) return
					setConfirmOpen(false)
					void setStatus(pending.id, pending.status, reason)
					setPending(null)
				}}
			/>
			<div className="flex items-end justify-between">
				<div>
					<h2 className="text-base font-semibold">Coin Types</h2>
					<p className="mt-1 text-sm text-gray-400">Admin cannot delete coins. Only enable/disable.</p>
					{error ? <p className="mt-2 text-sm text-red-400">{error}</p> : null}
				</div>
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[760px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Coin</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Code</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Value (MWK)</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Used For</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{coins.length ? (
							coins.map((c) => {
								const usedFor =
									c.code.toLowerCase() === 'diamond'
										? 'Premium'
										: c.code.toLowerCase() === 'gold'
											? 'Battles'
											: 'Gifts'
								const isBusy = busyId === c.id
								return (
									<tr key={c.id}>
										<td className="border-b border-white/10 py-3 pr-4 font-medium">{c.name}</td>
										<td className="border-b border-white/10 py-3 pr-4 text-gray-300">{c.code}</td>
										<td className="border-b border-white/10 py-3 pr-4">{c.value_mwk}</td>
										<td className="border-b border-white/10 py-3 pr-4">{usedFor}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{c.status === 'active' ? (
												<span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Active</span>
											) : (
												<span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Disabled</span>
											)}
										</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{c.status === 'active' ? (
												<button
													disabled={isBusy}
													onClick={() => requestChange(c, 'disabled')}
													className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm disabled:opacity-60"
												>
													{isBusy ? 'Saving…' : 'Disable'}
												</button>
											) : (
												<button
													disabled={isBusy}
													onClick={() => requestChange(c, 'active')}
													className="inline-flex h-9 items-center rounded-xl bg-emerald-600 px-3 text-sm disabled:opacity-60"
												>
													{isBusy ? 'Saving…' : 'Enable'}
												</button>
											)}
										</td>
									</tr>
								)
							})
						) : (
							<tr>
								<td colSpan={6} className="py-6 text-sm text-gray-400">
									No coins found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
