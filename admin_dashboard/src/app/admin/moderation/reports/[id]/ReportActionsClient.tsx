'use client'

import { useState } from 'react'

type Action = 'approve' | 'dismiss' | 'remove'

export function ReportActionsClient(props: { reportId: string; canRemove: boolean; isPending: boolean }) {
	const { reportId, canRemove, isPending } = props
	const [loading, setLoading] = useState<Action | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	async function run(action: Action) {
		setError(null)
		setOk(null)

		const confirmText: Record<Action, string> = {
			approve: 'Mark this report as reviewed?',
			dismiss: 'Dismiss this report? (No action will be taken on the content.)',
			remove: 'Queue this report for removal handling?',
		}

		if (!confirm(confirmText[action])) return

		setLoading(action)
		try {
			const res = await fetch(`/api/admin/moderation/reports/${reportId}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action, confirm: true }),
			})
			const json = (await res.json().catch(() => null)) as any
			if (!res.ok) throw new Error(json?.error || 'Request failed')
			setOk('Action completed.')
			// Refresh server component.
			window.location.reload()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Request failed')
		} finally {
			setLoading(null)
		}
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<h3 className="text-base font-semibold">Admin Actions</h3>
			<p className="mt-1 text-sm text-gray-400">These actions use the backend moderation review flow.</p>

			{error ? <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div> : null}
			{ok ? <div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200">{ok}</div> : null}

			<div className="mt-4 flex flex-wrap gap-2">
				{isPending ? (
					<button disabled={!!loading} onClick={() => run('approve')} className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60">
						Mark reviewed
					</button>
				) : null}
				{isPending ? (
					<button disabled={!!loading} onClick={() => run('dismiss')} className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60">
						Dismiss
					</button>
				) : null}
				{isPending && canRemove ? (
					<button disabled={!!loading} onClick={() => run('remove')} className="inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15 disabled:opacity-60">
						Queue removal
					</button>
				) : null}
			</div>

			{loading ? <p className="mt-3 text-xs text-gray-400">Working… {loading}</p> : null}
		</div>
	)
}
