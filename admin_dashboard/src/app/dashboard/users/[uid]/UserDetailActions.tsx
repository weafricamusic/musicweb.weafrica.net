'use client'

import { useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'

export function UserDetailActions(props: {
	uid: string
	email: string | null
	initialDisabled: boolean
}) {
	const { uid, email, initialDisabled } = props
	const router = useRouter()

	const [disabled, setDisabled] = useState(initialDisabled)
	const [reason, setReason] = useState('')
	const [loading, setLoading] = useState<null | 'toggle_disabled' | 'reset_password'>(null)
	const [error, setError] = useState<string | null>(null)
	const [resetLink, setResetLink] = useState<string | null>(null)

	async function patch(body: unknown) {
		const res = await fetch(`/api/admin/users/${encodeURIComponent(uid)}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body),
		})
		if (res.ok) return res
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function onToggleDisabled() {
		if (loading) return
		setError(null)
		setResetLink(null)
		setLoading('toggle_disabled')
		try {
			const next = !disabled
			await patch({ action: 'set_disabled', disabled: next, reason: reason.trim() || undefined })
			setDisabled(next)
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to update status')
		} finally {
			setLoading(null)
		}
	}

	async function onResetPassword() {
		if (loading) return
		setError(null)
		setResetLink(null)
		setLoading('reset_password')
		try {
			const res = await patch({ action: 'reset_password' })
			const data = (await res.json().catch(() => null)) as { link?: string; error?: string } | null
			if (!data?.link) throw new Error(data?.error || 'Failed to generate reset link')
			setResetLink(data.link)
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to generate reset link')
		} finally {
			setLoading(null)
		}
	}

	return (
		<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
			<h3 className="text-base font-semibold">Actions</h3>

			{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}

			<div className="mt-4 grid gap-3 md:grid-cols-2">
				<div>
					<label className="block text-sm text-zinc-600 dark:text-zinc-400">Block reason (optional)</label>
					<input
						value={reason}
						onChange={(e) => setReason(e.target.value)}
						disabled={!!loading}
						placeholder="Reason for blocking (optional)"
						className="mt-1 h-10 w-full rounded-xl border border-black/[.08] bg-transparent px-3 text-sm outline-none focus:ring-2 focus:ring-black/10 dark:border-white/[.145] dark:focus:ring-white/10"
					/>
					<p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">Saved to admin activity log (if enabled).</p>
				</div>

				<div>
					<label className="block text-sm text-zinc-600 dark:text-zinc-400">Status</label>
					<div className="mt-1 flex items-center gap-2">
						<span
							className={
								disabled
								? 'rounded-full bg-red-50 px-2 py-1 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300'
								: 'rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300'
							}
						>
							{disabled ? 'Blocked' : 'Active'}
						</span>
						<button
							type="button"
							disabled={!!loading}
							onClick={onToggleDisabled}
							className={`inline-flex h-10 items-center rounded-xl border px-4 text-sm disabled:opacity-60 dark:border-white/[.145] ${
								disabled ? 'border-black/[.08]' : 'border-black/[.08] text-red-700 dark:text-red-300'
							}`}
						>
							{loading === 'toggle_disabled' ? 'Saving…' : disabled ? 'Unblock user' : 'Block user'}
						</button>
					</div>
				</div>

				<div className="md:col-span-2">
					<label className="block text-sm text-zinc-600 dark:text-zinc-400">Password</label>
					<div className="mt-1 flex flex-wrap items-center gap-2">
						<button
							type="button"
							disabled={!!loading}
							onClick={onResetPassword}
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm disabled:opacity-60 dark:border-white/[.145]"
						>
							{loading === 'reset_password' ? 'Generating…' : 'Generate reset link'}
						</button>
						{resetLink ? (
							<button
								type="button"
								onClick={() => navigator.clipboard?.writeText(resetLink)}
								className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
							>
								Copy link
							</button>
						) : null}
					</div>
					{resetLink ? (
						<p className="mt-2 break-all text-xs text-zinc-600 dark:text-zinc-400">{resetLink}</p>
					) : (
						<p className="mt-2 text-xs text-zinc-600 dark:text-zinc-400">Creates a one-time Firebase password reset URL.</p>
					)}
				</div>

			</div>
		</div>
	)
}
