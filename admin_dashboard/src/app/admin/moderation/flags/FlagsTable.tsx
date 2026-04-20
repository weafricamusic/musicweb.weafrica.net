'use client'

import { useRouter, useSearchParams } from 'next/navigation'
import { useMemo, useState } from 'react'

export type FlagRow = {
	id: string
	content_type: string
	content_id: string
	reported_by: string
	reason: string
	severity: number
	status: string
	resolution: string | null
	resolution_notes: string | null
	resolved_by: string | null
	resolved_at: string | null
	created_at: string
}

export function FlagsTable(props: { rows: FlagRow[] }) {
	const { rows } = props
	const router = useRouter()
	const params = useSearchParams()
	const [busyId, setBusyId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [notesById, setNotesById] = useState<Record<string, string>>({})

	const status = params.get('status') ?? 'pending'
	const statusOptions = useMemo(() => ['pending', 'resolved', 'dismissed', 'all'], [])

	function setFilter(nextStatus: string) {
		const sp = new URLSearchParams(params.toString())
		sp.set('status', nextStatus)
		router.push(`/admin/moderation/flags?${sp.toString()}`)
	}

	async function resolveFlag(id: string, action: 'dismiss' | 'remove') {
		if (busyId) return
		setError(null)
		setBusyId(id)
		try {
			const res = await fetch(`/api/admin/content-flags/${encodeURIComponent(id)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action, notes: notesById[id] || undefined }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to resolve flag')
			}
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to resolve flag')
		} finally {
			setBusyId(null)
		}
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
				<div>
					<h2 className="text-base font-semibold">Content Flags</h2>
					<p className="mt-1 text-sm text-gray-400">Review and resolve moderation flags.</p>
					{error ? <p className="mt-2 text-sm text-red-400">{error}</p> : null}
				</div>
				<div>
					<label className="block text-xs text-gray-400">Status</label>
					<select
						value={status}
						onChange={(e) => setFilter(e.target.value)}
						className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm"
					>
						{statusOptions.map((value) => (
							<option key={value} value={value}>
								{value}
							</option>
						))}
					</select>
				</div>
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[1080px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Content</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Reason</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Severity</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Created</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Actions</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? rows.map((flag) => {
							const isBusy = busyId === flag.id
							return (
								<tr key={flag.id}>
									<td className="border-b border-white/10 py-3 pr-4">
										<p className="font-medium">{flag.content_type}:{flag.content_id}</p>
										<p className="text-xs text-gray-500">Reported by {flag.reported_by}</p>
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{flag.reason}</td>
									<td className="border-b border-white/10 py-3 pr-4">{flag.severity}</td>
									<td className="border-b border-white/10 py-3 pr-4">{flag.status}</td>
									<td className="border-b border-white/10 py-3 pr-4">{new Date(flag.created_at).toLocaleString()}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="flex flex-wrap items-center gap-2">
											<input
												value={notesById[flag.id] ?? ''}
												onChange={(e) => setNotesById((current) => ({ ...current, [flag.id]: e.target.value }))}
												placeholder="Notes (optional)"
												disabled={isBusy || flag.status !== 'pending'}
												className="h-9 w-44 rounded-xl border border-white/10 bg-black/20 px-3 text-xs outline-none disabled:opacity-60"
											/>
											{flag.status === 'pending' ? (
												<>
													<button
														type="button"
														disabled={isBusy}
														onClick={() => resolveFlag(flag.id, 'dismiss')}
														className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 disabled:opacity-60"
													>
														{isBusy ? 'Saving…' : 'Dismiss'}
													</button>
													<button
														type="button"
														disabled={isBusy}
														onClick={() => resolveFlag(flag.id, 'remove')}
														className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm disabled:opacity-60"
													>
														{isBusy ? 'Saving…' : 'Remove'}
													</button>
												</>
											) : null}
										</div>
									</td>
								</tr>
							)
						}) : (
							<tr>
								<td colSpan={6} className="py-6 text-sm text-gray-400">No flags found.</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}