'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'

type TargetPlan = 'all' | 'free' | 'premium'

type Promotion = {
	id: string
	title: string
	description: string | null
	image_url: string
	target_plan: TargetPlan
	is_active: boolean
	priority: number
	starts_at: string | null
	ends_at: string | null
	created_at: string
	updated_at: string
}

type ApiList = { ok: true; data: Promotion[] } | { ok: false; error: string }

type ApiToggle = { ok: true } | { ok: false; error: string }

function fmtDate(iso: string | null) {
	if (!iso) return '—'
	const d = new Date(iso)
	return Number.isNaN(d.getTime()) ? iso : d.toLocaleString()
}

export default function PromotionsAdminPage() {
	const [rows, setRows] = useState<Promotion[] | null>(null)
	const [busyId, setBusyId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)

	const reload = useCallback(async () => {
		setError(null)
		const res = await fetch('/api/admin/promotions', { method: 'GET' })
		const json = (await res.json().catch(() => null)) as ApiList | null
		if (!json) {
			setError(`Request failed (status ${res.status}).`)
			return
		}
		if (!res.ok || json.ok === false) {
			setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
			return
		}
		setRows(json.data)
	}, [])

	useEffect(() => {
		let cancelled = false
		void (async () => {
			if (cancelled) return
			await reload()
		})()
		return () => {
			cancelled = true
		}
	}, [reload])

	const filtered = useMemo(() => rows ?? [], [rows])

	async function toggleActive(p: Promotion, nextActive: boolean) {
		setOk(null)
		setError(null)
		setBusyId(p.id)
		try {
			const res = await fetch(`/api/admin/promotions/${encodeURIComponent(p.id)}/${nextActive ? 'activate' : 'deactivate'}`, {
				method: 'PATCH',
			})
			const json = (await res.json().catch(() => null)) as ApiToggle | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || json.ok === false) {
				setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			await reload()
			setOk(nextActive ? 'Activated.' : 'Deactivated.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Request failed.')
		} finally {
			setBusyId(null)
		}
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between gap-4">
				<div>
					<h1 className="text-2xl font-bold">Promotions</h1>
					<p className="mt-1 text-sm text-gray-400">Create, update, activate, and deactivate promotions.</p>
					<p className="mt-2 text-xs text-gray-500">
						Consumer reads{' '}
						<a className="underline hover:text-gray-300" href="/api/promotions" target="_blank" rel="noreferrer">
							/api/promotions
						</a>
						{' '}— only active promos in the current schedule window are returned.
					</p>
				</div>
				<Link
					href="/admin/content/promotions/new"
					className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90"
				>
					New promotion
				</Link>
			</div>

			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}
			{ok ? <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div> : null}

			<div className="overflow-hidden rounded-2xl border border-white/10">
				<div className="overflow-x-auto">
					<table className="min-w-full text-sm">
						<thead className="bg-white/5 text-left text-xs text-gray-400">
							<tr>
								<th className="px-4 py-3">Title</th>
								<th className="px-4 py-3">Target</th>
								<th className="px-4 py-3">Priority</th>
								<th className="px-4 py-3">Window</th>
								<th className="px-4 py-3">Status</th>
								<th className="px-4 py-3">Actions</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10">
							{rows == null ? (
								<tr>
									<td className="px-4 py-4 text-gray-400" colSpan={6}>
										Loading…
									</td>
								</tr>
							) : filtered.length ? (
								filtered.map((r) => (
									<tr key={r.id} className="bg-black/10">
										<td className="px-4 py-3">
											<div className="font-medium">{r.title}</div>
											<div className="mt-1 text-xs text-gray-500">Updated: {fmtDate(r.updated_at)}</div>
										</td>
										<td className="px-4 py-3 text-gray-200">{r.target_plan}</td>
										<td className="px-4 py-3 text-gray-200">{r.priority}</td>
										<td className="px-4 py-3 text-gray-300">
											<div className="text-xs">Start: {fmtDate(r.starts_at)}</div>
											<div className="text-xs">End: {fmtDate(r.ends_at)}</div>
										</td>
										<td className="px-4 py-3">
											<span
												className={
													'inline-flex rounded-full px-2 py-1 text-xs ' +
													(r.is_active
														? 'bg-emerald-500/15 text-emerald-200 border border-emerald-500/30'
														: 'bg-zinc-500/10 text-zinc-300 border border-white/10')
												}
											>
												{r.is_active ? 'Active' : 'Inactive'}
											</span>
										</td>
										<td className="px-4 py-3">
											<div className="flex flex-wrap items-center gap-2">
												<Link
													href={`/admin/content/promotions/${encodeURIComponent(r.id)}`}
													className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
												>
													Edit
												</Link>
												<button
													type="button"
													disabled={busyId === r.id}
													onClick={() => toggleActive(r, !r.is_active)}
													className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5 disabled:opacity-60"
												>
													{busyId === r.id ? 'Working…' : r.is_active ? 'Deactivate' : 'Activate'}
												</button>
											</div>
										</td>
									</tr>
								))
							) : (
								<tr>
									<td className="px-4 py-4 text-gray-400" colSpan={6}>
										No promotions yet.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>
		</div>
	)
}
