'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

type Status = 'pending' | 'active' | 'blocked'

type Entity = 'artists' | 'djs'

function normalizeStatus(status: string | null | undefined): Status {
	const v = String(status ?? '').toLowerCase().trim()
	if (v === 'active' || v === 'approved') return 'active'
	if (v === 'blocked' || v === 'suspended') return 'blocked'
	return 'pending'
}

export default function CreatorRowActions(props: {
	entity: Entity
	id: string
	name?: string | null
	status?: string | null
	disabled?: boolean
}) {
	const { entity, id, name, status, disabled } = props
	const router = useRouter()
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState<string | null>(null)

	const s = normalizeStatus(status)

	async function patch(body: unknown) {
		const url = `/api/admin/${entity}/${encodeURIComponent(id)}`
		const res = await fetch(url, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body),
		})
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function del() {
		const url = `/api/admin/${entity}/${encodeURIComponent(id)}`
		const res = await fetch(url, { method: 'DELETE' })
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Delete failed')
	}

	async function run(label: string, fn: () => Promise<void>) {
		if (loading || disabled) return
		setError(null)
		setLoading(true)
		try {
			await fn()
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : `Failed to ${label}`)
		} finally {
			setLoading(false)
		}
	}

	const displayName = name?.trim() ? name.trim() : id

	return (
		<div className="space-y-2">
			{error ? <div className="text-xs text-red-300">{error}</div> : null}
			<div className="flex flex-wrap gap-2">
				{s !== 'active' ? (
					<button
						type="button"
						disabled={loading || disabled}
						onClick={() => run('approve', () => patch({ action: 'set_status', status: 'active' }))}
						className="rounded-lg bg-green-600 px-3 py-1.5 text-xs font-medium hover:bg-green-700 disabled:opacity-60"
					>
						{loading ? 'Saving…' : 'Approve'}
					</button>
				) : null}

				{s !== 'pending' ? (
					<button
						type="button"
						disabled={loading || disabled}
						onClick={() => run('reject', () => patch({ action: 'set_status', status: 'pending' }))}
						className="rounded-lg bg-zinc-700 px-3 py-1.5 text-xs font-medium hover:bg-zinc-600 disabled:opacity-60"
					>
						{loading ? 'Saving…' : 'Reject'}
					</button>
				) : null}

				{s !== 'blocked' ? (
					<button
						type="button"
						disabled={loading || disabled}
						onClick={() => {
							if (!confirm(`Suspend ${displayName}? This will disable login.`)) return
							return run('suspend', () => patch({ action: 'set_status', status: 'blocked' }))
						}}
						className="rounded-lg bg-amber-600 px-3 py-1.5 text-xs font-medium hover:bg-amber-700 disabled:opacity-60"
					>
						{loading ? 'Saving…' : 'Suspend'}
					</button>
				) : (
					<button
						type="button"
						disabled={loading || disabled}
						onClick={() => run('reactivate', () => patch({ action: 'set_status', status: 'active' }))}
						className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-medium hover:bg-blue-700 disabled:opacity-60"
					>
						{loading ? 'Saving…' : 'Reactivate'}
					</button>
				)}

				<button
					type="button"
					disabled={loading || disabled}
					onClick={() => {
						if (!confirm(`Delete ${displayName}? This cannot be undone.`)) return
						return run('delete', del)
					}}
					className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-medium hover:bg-red-700 disabled:opacity-60"
				>
					{loading ? 'Deleting…' : 'Delete'}
				</button>
			</div>
		</div>
	)
}
