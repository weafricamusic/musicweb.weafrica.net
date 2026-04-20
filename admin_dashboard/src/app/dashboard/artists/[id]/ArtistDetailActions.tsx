'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

type ArtistStatus = 'pending' | 'active' | 'blocked'

function normalizeStatus(status: string | null | undefined): ArtistStatus {
	const raw = String(status ?? '').toLowerCase().trim()
	if (raw === 'active' || raw === 'approved') return 'active'
	if (raw === 'blocked') return 'blocked'
	return 'pending'
}

export function ArtistDetailActions(props: { id: string; name: string | null; status?: string | null; verified?: boolean }) {
	const { id, name, status, verified } = props
	const router = useRouter()
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const s = normalizeStatus(status)

	async function patch(body: unknown) {
		const res = await fetch(`/api/admin/artists/${encodeURIComponent(id)}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body),
		})
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function setStatus(next: ArtistStatus) {
		if (loading) return
		setError(null)
		setLoading(true)
		try {
			await patch({ action: 'set_status', status: next })
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update artist')	
		} finally {
			setLoading(false)
		}
	}

	async function toggleVerified(next: boolean) {
		if (loading) return
		setError(null)
		setLoading(true)
		try {
			await patch({ action: 'set_verified', verified: next })
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update verification')
		} finally {
			setLoading(false)
		}
	}

	async function resetAccess() {
		if (loading) return
		if (!confirm(`Reset access for ${name || id}?`)) return
		setError(null)
		setLoading(true)
		try {
			await patch({ action: 'reset_access' })
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to reset access')
		} finally {
			setLoading(false)
		}
	}

	return (
		<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
			<h3 className="text-base font-semibold">Actions</h3>
			{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}

			<div className="mt-4 flex flex-wrap gap-2">
				{s === 'pending' ? (
					<button
						type="button"
						disabled={loading}
						onClick={() => setStatus('active')}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
					>
						{loading ? 'Saving…' : 'Approve artist'}
					</button>
				) : null}

				{s !== 'blocked' ? (
					<button
						type="button"
						disabled={loading}
						onClick={() => setStatus('blocked')}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm text-red-700 disabled:opacity-60 dark:border-white/[.145] dark:text-red-300"
					>
						{loading ? 'Saving…' : 'Block artist'}
					</button>
				) : (
					<button
						type="button"
						disabled={loading}
						onClick={() => setStatus('pending')}
						className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
					>
						{loading ? 'Saving…' : 'Unblock artist'}
					</button>
				)}

				<button
					type="button"
					disabled={loading}
					onClick={() => toggleVerified(!(verified === true))}
					className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
				>
					{loading ? 'Saving…' : verified ? 'Unverify artist' : 'Verify artist'}
				</button>

				<button
					type="button"
					disabled={loading}
					onClick={resetAccess}
					className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
				>
					{loading ? 'Saving…' : 'Reset access'}
				</button>
			</div>
		</div>
	)
}
