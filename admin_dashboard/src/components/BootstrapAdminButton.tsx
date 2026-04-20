'use client'

import { useState } from 'react'

export function BootstrapAdminButton() {
	const [loading, setLoading] = useState(false)
	const [error, setError] = useState<string | null>(null)

	async function onClick() {
		setLoading(true)
		setError(null)
		try {
			const res = await fetch('/api/admin/bootstrap', { method: 'POST' })
			const body = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null
			if (!res.ok) throw new Error(body?.error || 'Bootstrap failed')
			window.location.reload()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Bootstrap failed')
		} finally {
			setLoading(false)
		}
	}

	return (
		<div className="mt-4">
			<button
				onClick={onClick}
				disabled={loading}
				className="h-10 rounded-xl bg-foreground px-4 text-sm text-background disabled:opacity-60"
			>
				{loading ? 'Setting up…' : 'Make me super admin'}
			</button>
			{error ? <div className="mt-2 text-sm text-red-600 dark:text-red-400">{error}</div> : null}
		</div>
	)
}
