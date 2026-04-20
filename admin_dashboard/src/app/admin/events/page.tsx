'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'

const STATUS_OPTIONS = ['all', 'draft', 'published', 'cancelled'] as const

type EventRow = {
	id: string
	title: string
	description: string | null
	cover_image_url: string
	venue_name: string | null
	venue_address: string | null
	city: string | null
	country_code: string | null
	starts_at: string
	ends_at: string | null
	timezone: string
	status: 'draft' | 'published' | 'cancelled'
	created_by_admin_email: string | null
	created_at: string
	updated_at: string
}

type ApiList = { ok: true; data: EventRow[] } | { ok: false; error: string }

function fmtDate(iso: string | null) {
	if (!iso) return '—'
	const d = new Date(iso)
	return Number.isNaN(d.getTime()) ? iso : d.toLocaleString()
}

function statusBadge(status: EventRow['status']) {
	switch (status) {
		case 'published':
			return 'bg-emerald-500/15 text-emerald-200 border border-emerald-500/30'
		case 'cancelled':
			return 'bg-red-500/15 text-red-200 border border-red-500/30'
		default:
			return 'bg-zinc-500/10 text-zinc-300 border border-white/10'
	}
}

export default function EventsAdminPage() {
	const [rows, setRows] = useState<EventRow[] | null>(null)
	const [busy, setBusy] = useState(false)
	const [error, setError] = useState<string | null>(null)
	const [query, setQuery] = useState('')
	const [status, setStatus] = useState<(typeof STATUS_OPTIONS)[number]>('all')

	const load = useCallback(async () => {
		setError(null)
		setBusy(true)
		try {
			const params = new URLSearchParams()
			if (query.trim()) params.set('q', query.trim())
			if (status !== 'all') params.set('status', status)
			params.set('limit', '200')

			const res = await fetch(`/api/admin/events?${params.toString()}`, { method: 'GET' })
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
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Request failed.')
		} finally {
			setBusy(false)
		}
	}, [query, status])

	useEffect(() => {
		void load()
	}, [load])

	const filtered = useMemo(() => rows ?? [], [rows])

	return (
		<div className="space-y-6">
			<div className="flex items-start justify-between gap-4">
				<div>
					<h1 className="text-2xl font-bold">Events & Tickets</h1>
					<p className="mt-1 text-sm text-gray-400">Create events, manage ticket types, and sell tickets.</p>
				</div>
				<Link
					href="/admin/events/new"
					className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90"
				>
					New event
				</Link>
			</div>

			<div className="flex flex-wrap items-center gap-3">
				<div className="flex items-center gap-2">
					<input
						value={query}
						onChange={(e) => setQuery(e.target.value)}
						placeholder="Search title"
						className="h-10 w-64 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none focus:border-white/20"
					/>
					<select
						value={status}
						onChange={(e) => setStatus(e.target.value as typeof status)}
						className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none focus:border-white/20"
					>
						{STATUS_OPTIONS.map((s) => (
							<option key={s} value={s}>
								{s}
							</option>
						))}
					</select>
					<button
						type="button"
						onClick={() => void load()}
						disabled={busy}
						className="h-10 rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60"
					>
						{busy ? 'Refreshing…' : 'Refresh'}
					</button>
				</div>
			</div>

			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}

			<div className="overflow-hidden rounded-2xl border border-white/10">
				<div className="overflow-x-auto">
					<table className="min-w-full text-sm">
						<thead className="bg-white/5 text-left text-xs text-gray-400">
							<tr>
								<th className="px-4 py-3">Event</th>
								<th className="px-4 py-3">Schedule</th>
								<th className="px-4 py-3">Location</th>
								<th className="px-4 py-3">Status</th>
								<th className="px-4 py-3">Actions</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10">
							{rows == null ? (
								<tr>
									<td className="px-4 py-4 text-gray-400" colSpan={5}>
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
										<td className="px-4 py-3 text-xs text-gray-300">
											<div>Start: {fmtDate(r.starts_at)}</div>
											<div>End: {fmtDate(r.ends_at)}</div>
										</td>
										<td className="px-4 py-3 text-xs text-gray-300">
											{[r.city, r.country_code].filter(Boolean).join(', ') || r.venue_name || '—'}
										</td>
										<td className="px-4 py-3">
											<span className={`inline-flex rounded-full px-2 py-1 text-xs ${statusBadge(r.status)}`}>
												{r.status}
											</span>
										</td>
										<td className="px-4 py-3">
											<Link
												href={`/admin/events/${encodeURIComponent(r.id)}`}
												className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
											>
												Manage
											</Link>
										</td>
									</tr>
								))
							) : (
								<tr>
									<td className="px-4 py-4 text-gray-400" colSpan={5}>
										No events yet.
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
