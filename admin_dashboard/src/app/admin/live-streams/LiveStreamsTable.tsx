'use client'

import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useMemo, useState } from 'react'

export type LiveStreamRow = {
	id: string
	channelName: string
	streamerName: string
	streamerAvatarUrl: string | null
	hostType: 'dj' | 'artist'
	streamType: 'dj_live' | 'artist_live' | 'battle'
	status: 'live' | 'ended'
	viewers: number
	startedAt: string | null
	region: string
}

function formatTime(ts: string | null): string {
	if (!ts) return '—'
	const d = new Date(ts)
	if (Number.isNaN(d.getTime())) return '—'
	return d.toLocaleString()
}

function typeLabel(t: LiveStreamRow['streamType']): string {
	if (t === 'battle') return 'Battle'
	if (t === 'artist_live') return 'Artist Live'
	return 'DJ Live'
}

function statusLabel(s: LiveStreamRow['status']): string {
	return s === 'live' ? 'Live' : 'Ended'
}

export function LiveStreamsTable(props: {
	rows: LiveStreamRow[]
	activeCount: number
}) {
	const { rows, activeCount } = props
	const router = useRouter()
	const params = useSearchParams()
	const [stoppingId, setStoppingId] = useState<string | null>(null)
	const [reasonById, setReasonById] = useState<Record<string, string>>({})
	const [error, setError] = useState<string | null>(null)

	const status = params.get('status') ?? 'live'
	const region = params.get('region') ?? 'MW'

	const regionOptions = useMemo(() => {
		const found = new Set<string>()
		rows.forEach((r) => found.add((r.region || 'MW').toUpperCase()))
		const others = [...found].filter((r) => r !== 'MW').sort()
		return ['MW', ...others]
	}, [rows])

	function setFilter(next: { status?: string; region?: string }) {
		const sp = new URLSearchParams(params.toString())
		if (next.status != null) sp.set('status', next.status)
		if (next.region != null) sp.set('region', next.region)
		router.push(`/admin/live-streams?${sp.toString()}`)
	}

	async function stopStream(id: string) {
		if (stoppingId) return
		setError(null)
		setStoppingId(id)
		try {
			const res = await fetch(`/api/admin/live-streams/${encodeURIComponent(id)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'stop_stream', reason: reasonById[id] || undefined }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to stop stream')
			}
			router.refresh()
		} catch (e) {
			setError(e instanceof Error ? e.message : 'Failed to stop stream')
		} finally {
			setStoppingId(null)
		}
	}

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
				<div>
					<h2 className="text-base font-semibold">Live Streams</h2>
					<p className="mt-1 text-sm text-gray-400">Active live count: {activeCount}</p>
					{error ? <p className="mt-2 text-sm text-red-400">{error}</p> : null}
				</div>

				<div className="flex flex-wrap gap-3">
					<div>
						<label className="block text-xs text-gray-400">Status</label>
						<select
							value={status}
							onChange={(e) => setFilter({ status: e.target.value })}
							className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm"
						>
							<option value="live">Live</option>
							<option value="ended">Ended</option>
							<option value="all">All</option>
						</select>
					</div>

					<div>
						<label className="block text-xs text-gray-400">Region</label>
						<select
							value={region}
							onChange={(e) => setFilter({ region: e.target.value })}
							className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm"
						>
							{regionOptions.map((r) => (
								<option key={r} value={r}>
									{r}
								</option>
							))}
						</select>
					</div>
				</div>
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Streamer</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Type</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Viewers</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Start time</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Region</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Actions</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((s) => (
								<tr key={s.id}>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="flex items-center gap-3">
											{s.streamerAvatarUrl ? (
												<img
													alt=""
													src={s.streamerAvatarUrl}
													className="h-9 w-9 rounded-full border border-white/10 object-cover"
												/>
											) : (
												<div className="h-9 w-9 rounded-full border border-white/10 bg-white/5" />
											)}
											<div className="min-w-0">
												<p className="truncate font-medium">{s.streamerName}</p>
												<p className="truncate text-xs text-gray-400">{s.channelName}</p>
											</div>
										</div>
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{typeLabel(s.streamType)}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										{s.status === 'live' ? (
											<span className="inline-flex items-center gap-2 rounded-full bg-red-500/10 px-2 py-1 text-xs text-red-300">
												<span className="h-2 w-2 rounded-full bg-red-500" /> Live
											</span>
										) : (
											<span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">{statusLabel(s.status)}</span>
										)}
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{s.viewers}</td>
									<td className="border-b border-white/10 py-3 pr-4">{formatTime(s.startedAt)}</td>
									<td className="border-b border-white/10 py-3 pr-4">{(s.region || 'MW').toUpperCase()}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="flex flex-wrap items-center gap-2">
											<Link
												href={`/admin/live-streams/${encodeURIComponent(s.id)}`}
												className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5"
											>
												View
											</Link>
											{s.status === 'live' ? (
												<div className="flex items-center gap-2">
													<input
														value={reasonById[s.id] ?? ''}
														onChange={(e) => setReasonById((m) => ({ ...m, [s.id]: e.target.value }))}
														placeholder="Reason (optional)"
														disabled={stoppingId === s.id}
														className="h-9 w-44 rounded-xl border border-white/10 bg-black/20 px-3 text-xs outline-none disabled:opacity-60"
													/>
													<button
														type="button"
														disabled={stoppingId === s.id}
														onClick={() => stopStream(s.id)}
														className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm disabled:opacity-60"
													>
														{stoppingId === s.id ? 'Stopping…' : 'Stop'}
													</button>
												</div>
											) : null}
										</div>
									</td>
								</tr>
							))
						) : (
							<tr>
								<td colSpan={7} className="py-6 text-sm text-gray-400">
									No streams found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
