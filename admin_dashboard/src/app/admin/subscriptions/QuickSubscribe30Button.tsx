'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'

type ApiResponse =
	| { ok: true; subscription_id: number; transaction_id: number | null; warning?: string }
	| { error: string }

export default function QuickSubscribe30Button(props: {
	userId: string
	planId: string
	source?: string
	className?: string
	compact?: boolean
}) {
	const userId = String(props.userId ?? '').trim()
	const planId = String(props.planId ?? '').trim().toLowerCase()
	const source = typeof props.source === 'string' && props.source.trim() ? props.source.trim() : 'admin_creator_directory'
	const router = useRouter()

	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)

	async function subscribe30Days() {
		if (!userId || !planId) return
		setBusy(true)
		setError(null)
		try {
			const payload = {
				action: 'set_user_subscription',
				user_id: userId,
				plan_id: planId,
				duration_minutes: 30 * 24 * 60,
				months: 0,
				auto_renew: false,
				create_transaction: false,
				source,
			}

			const res = await fetch('/api/admin/subscriptions/tools', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(payload),
			})

			const json = (await res.json().catch(() => null)) as ApiResponse | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}

			router.refresh()
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Request failed.')
		} finally {
			setBusy(false)
		}
	}

	const buttonClass =
		props.className ??
		(props.compact
			? 'inline-flex h-9 items-center rounded-xl bg-white px-3 text-xs font-medium text-black hover:bg-white/90 disabled:opacity-60'
			: 'inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60')

	return (
		<div className="inline-flex flex-col items-start gap-1">
			<button
				type="button"
				onClick={subscribe30Days}
				disabled={busy || !userId || !planId}
				className={buttonClass}
				title={planId ? `Subscribes for 30 days using plan_id="${planId}"` : 'Plan not configured'}
			>
				{busy ? 'Subscribing…' : 'Subscribe 30 days'}
			</button>
			{error ? <span className="text-xs text-red-200">{error}</span> : null}
		</div>
	)
}
