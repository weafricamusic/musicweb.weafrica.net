'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

export function StreamActions(props: { id: string; status: 'live' | 'ended' }) {
	const { id, status } = props
	const router = useRouter()
	const [reason, setReason] = useState('')
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState<string | null>(null)

	async function stop() {
		if (loading) return
		setError(null)
		setLoading(true)
		try {
			const res = await fetch(`/api/admin/live-streams/${encodeURIComponent(id)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'stop_stream', reason: reason.trim() || undefined }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to stop stream')
			}
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to stop stream')
		} finally {
			setLoading(false)
		}
	}

	if (status !== 'live') return null

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<h3 className="text-base font-semibold">Stop stream</h3>
			<p className="mt-1 text-sm text-gray-400">Kicks the channel in Agora and marks it as ended in Supabase.</p>
			{error ? <p className="mt-3 text-sm text-red-400">{error}</p> : null}
			<div className="mt-4 flex flex-col gap-2 md:flex-row md:items-center">
				<input
					value={reason}
					onChange={(e) => setReason(e.target.value)}
					disabled={loading}
					placeholder="Reason (optional)"
					className="h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none disabled:opacity-60"
				/>
				<button
					type="button"
					disabled={loading}
					onClick={stop}
					className="inline-flex h-10 items-center justify-center rounded-xl bg-red-600 px-4 text-sm disabled:opacity-60"
				>
					{loading ? 'Stopping…' : 'Stop stream'}
				</button>
			</div>
		</div>
	)
}
