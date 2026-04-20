'use client'

import { useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'

type DjStatus = 'pending' | 'active' | 'blocked'

export function DjDetailActions(props: { id: string; name: string | null; initialStatus: DjStatus }) {
	const { id, name, initialStatus } = props
	const router = useRouter()
	const [status, setStatus] = useState<DjStatus>(initialStatus)
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState<string | null>(null)

	const isBlocked = status === 'blocked'
	const isPending = status === 'pending'

	const statusLabel = useMemo(() => {
		if (status === 'active') return 'Active'
		if (status === 'blocked') return 'Blocked'
		return 'Pending'
	}, [status])

	async function updateStatus(next: DjStatus) {
		if (loading) return
		setError(null)
		setLoading(true)
		try {
			const res = await fetch(`/api/admin/djs/${encodeURIComponent(id)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'set_status', status: next }),
			})
			if (!res.ok) {
				const data = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(data?.error || 'Failed to update DJ')
			}
			setStatus(next)
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update DJ')
		} finally {
			setLoading(false)
		}
	}

	return (
		<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
			<h3 className="text-base font-semibold">Actions</h3>
			<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Current status: {statusLabel}</p>
			{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}

			<div className="mt-4 flex flex-wrap items-center gap-2">
				{isPending ? (
					<button
						type="button"
						disabled={loading}
						onClick={() => updateStatus('active')}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
					>
						{loading ? 'Saving…' : 'Approve DJ'}
					</button>
				) : null}

				{!isBlocked ? (
					<button
						type="button"
						disabled={loading}
						onClick={() => updateStatus('blocked')}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm text-red-700 disabled:opacity-60 dark:border-white/[.145] dark:text-red-300"
					>
						{loading ? 'Saving…' : `Block DJ${name ? ` (${name})` : ''}`}
					</button>
				) : (
					<button
						type="button"
						disabled={loading}
						onClick={() => updateStatus('pending')}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
					>
						{loading ? 'Saving…' : 'Unblock DJ'}
					</button>
				)}
			</div>

			<p className="mt-3 text-xs text-zinc-600 dark:text-zinc-400">
				Note: DJs are not deleted permanently; use Block.
			</p>
		</div>
	)
}
