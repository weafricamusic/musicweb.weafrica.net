'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'

type PlanId = 'free' | 'premium' | 'platinum'

type Promotion = {
	id: string
	target_plan_id: PlanId | null
	title: string | null
	body: string
	status: 'draft' | 'published' | 'archived'
	starts_at: string | null
	ends_at: string | null
	created_by: string | null
	created_at: string
	updated_at: string
}

type ApiList = { ok: true; promotions: Promotion[] } | { error: string }

type ApiCreate = { ok: true; promotion: Promotion } | { error: string }

type ApiPatch = { ok: true; promotion: Promotion } | { error: string }

export default function SubscriptionsPromotionsPage() {
	const [rows, setRows] = useState<Promotion[] | null>(null)
	const [filter, setFilter] = useState<PlanId | 'all'>('all')
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	// create form
	const [target, setTarget] = useState<PlanId | 'all'>('all')
	const [title, setTitle] = useState('')
	const [body, setBody] = useState('')
	const [status, setStatus] = useState<'draft' | 'published'>('published')

	useEffect(() => {
		let cancelled = false
		async function load() {
			setError(null)
			const res = await fetch('/api/admin/subscriptions/promotions', { method: 'GET' })
			const json = (await res.json().catch(() => null)) as ApiList | null
			if (cancelled) return
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setRows(json.promotions)
		}
		void load()
		return () => {
			cancelled = true
		}
	}, [])

	const filtered = useMemo(() => {
		const all = rows ?? []
		if (filter === 'all') return all
		return all.filter((r) => r.target_plan_id === filter)
	}, [rows, filter])

	async function create() {
		setOk(null)
		setError(null)
		const text = body.trim()
		if (!text) {
			setError('Message body is required.')
			return
		}

		setBusy(true)
		try {
			const res = await fetch('/api/admin/subscriptions/promotions', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					target_plan_id: target === 'all' ? null : target,
					title: title.trim() || null,
					body: text,
					status,
				}),
			})
			const json = (await res.json().catch(() => null)) as ApiCreate | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setRows((prev) => [json.promotion, ...(prev ?? [])])
			setTitle('')
			setBody('')
			setOk('Created.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Create failed.')
		} finally {
			setBusy(false)
		}
	}

	async function archive(id: string) {
		setOk(null)
		setError(null)
		setBusy(true)
		try {
			const res = await fetch('/api/admin/subscriptions/promotions', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ id, status: 'archived' }),
			})
			const json = (await res.json().catch(() => null)) as ApiPatch | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || 'error' in json) {
				setError('error' in json ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setRows((prev) => (prev ? prev.map((r) => (r.id === id ? json.promotion : r)) : prev))
			setOk('Archived.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Update failed.')
		} finally {
			setBusy(false)
		}
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Subscription Promotions</h1>
					<p className="mt-1 text-sm text-gray-400">Create upgrade nudges and VIP announcements by plan.</p>
					<p className="mt-2 text-xs text-gray-500">
						Consumer reads{' '}
						<a className="underline hover:text-gray-300" href="/api/subscriptions/promotions" target="_blank" rel="noreferrer">
							/api/subscriptions/promotions
						</a>
						{' '}— use status Published and ensure schedule windows (if set) include now.
					</p>
				</div>
				<Link href="/admin/subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div>
			) : null}
			{ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div>
			) : null}

			<div className="grid gap-6 md:grid-cols-2">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">New message</h2>
					<div className="mt-4 grid grid-cols-1 gap-3">
						<div>
							<label className="text-xs text-gray-400">Target</label>
							<select
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={target}
								onChange={(e) => setTarget(e.target.value as any)}
							>
								<option value="all">All subscriptions</option>
								<option value="free">Free</option>
								<option value="premium">Premium</option>
								<option value="platinum">Platinum</option>
							</select>
						</div>

						<div>
							<label className="text-xs text-gray-400">Title (optional)</label>
							<input
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={title}
								onChange={(e) => setTitle(e.target.value)}
								placeholder="Upgrade to Premium"
							/>
						</div>

						<div>
							<label className="text-xs text-gray-400">Message</label>
							<textarea
								rows={6}
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={body}
								onChange={(e) => setBody(e.target.value)}
								placeholder="Premium gives you 100% content access, no ads, and live battles."
							/>
						</div>

						<div className="flex items-center justify-between gap-3">
							<div>
								<label className="text-xs text-gray-400">Status</label>
								<select
									className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
									value={status}
									onChange={(e) => setStatus(e.target.value as any)}
								>
									<option value="published">Published</option>
									<option value="draft">Draft</option>
								</select>
							</div>
							<button
								type="button"
								onClick={create}
								disabled={busy}
								className="mt-5 inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
							>
								{busy ? 'Working…' : 'Create'}
							</button>
						</div>
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Messages</h2>
					<div className="mt-4 flex items-center gap-2">
						<label className="text-xs text-gray-400">Filter</label>
						<select
							className="h-9 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none focus:border-white/20"
							value={filter}
							onChange={(e) => setFilter(e.target.value as any)}
						>
							<option value="all">All</option>
							<option value="free">Free</option>
							<option value="premium">Premium</option>
							<option value="platinum">Platinum</option>
						</select>
					</div>

					<div className="mt-4 space-y-3">
						{filtered.length ? (
							filtered.map((r) => (
								<div key={r.id} className="rounded-xl border border-white/10 bg-black/10 p-4">
									<div className="flex items-start justify-between gap-4">
										<div>
											<p className="text-sm font-semibold">{r.title ?? 'Message'}</p>
											<p className="mt-1 text-xs text-gray-400">Target: {r.target_plan_id ?? 'all'} • Status: {r.status}</p>
										</div>
										<button
											type="button"
											onClick={() => archive(r.id)}
											disabled={busy || r.status === 'archived'}
											className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5 disabled:opacity-60"
										>
											Archive
										</button>
									</div>
									<p className="mt-3 text-sm text-gray-200 whitespace-pre-wrap">{r.body}</p>
									<p className="mt-3 text-xs text-gray-500">Created: {new Date(r.created_at).toLocaleString()}</p>
								</div>
							))
						) : (
							<p className="text-sm text-gray-400">No messages yet.</p>
						)}
					</div>
				</div>
			</div>
		</div>
	)
}
