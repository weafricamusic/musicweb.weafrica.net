'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'

import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'

export type TrackRow = {
	id: string
	title?: string | null
	name?: string | null
	artist_id?: string | null
	artistId?: string | null
	approved?: boolean | null
	is_active?: boolean | null
	isActive?: boolean | null
	created_at?: string | null
	createdAt?: string | null
	[key: string]: unknown
}

type TrackFilter = 'pending' | 'live' | 'removed'

type ConfirmState =
	| null
	| {
			id: string
			action: 'approve' | 'take_down' | 'restore'
			title: string
			description: string
			tone: 'primary' | 'danger'
	  }

type TableRow = {
	id: string
	title: string
	artistId: string | null
	approved: boolean
	isActive: boolean
	createdAt: string | null
	status: TrackFilter
	searchText: string
}

function normalizeTrackTitle(t: TrackRow): string {
	const candidates = [t.title, t.name, t['song_title'], t['track_title']]
	for (const c of candidates) {
		if (typeof c === 'string') {
			const v = c.trim()
			if (v) return v
		}
	}
	return String(t.id)
}

function normalizeArtistId(t: TrackRow): string | null {
	const candidates = [t.artist_id, t.artistId, t['artist_uuid'], t['creator_id']]
	for (const c of candidates) {
		if (typeof c === 'string') {
			const v = c.trim()
			if (v) return v
		}
	}
	return null
}

function normalizeApproved(t: TrackRow): boolean {
	return t.approved === true
}

function normalizeIsActive(t: TrackRow): boolean {
	if (t.is_active === false || t.isActive === false) return false
	return true
}

function normalizeCreatedAt(t: TrackRow): string | null {
	const v = t.created_at ?? t.createdAt
	if (typeof v === 'string') return v
	return null
}

function statusFor(t: TrackRow): TrackFilter {
	const approved = normalizeApproved(t)
	const isActive = normalizeIsActive(t)
	if (!approved) return 'pending'
	if (!isActive) return 'removed'
	return 'live'
}

function labelFilter(filter: TrackFilter): string {
	if (filter === 'pending') return 'Pending'
	if (filter === 'live') return 'Live'
	return 'Removed'
}

function formatDate(value: string | null): string {
	if (!value) return '—'
	const d = new Date(value)
	if (Number.isNaN(d.getTime())) return '—'
	return d.toLocaleString()
}

export function TracksTable(props: { tracks: TrackRow[]; filter: TrackFilter }) {
	const router = useRouter()
	const [loadingId, setLoadingId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<ConfirmState>(null)

	const rows = useMemo<TableRow[]>(() => {
		return (props.tracks ?? []).map((t) => {
			const title = normalizeTrackTitle(t)
			const artistId = normalizeArtistId(t)
			const approved = normalizeApproved(t)
			const isActive = normalizeIsActive(t)
			const createdAt = normalizeCreatedAt(t)
			const status = statusFor(t)
			return {
				id: String(t.id),
				title,
				artistId,
				approved,
				isActive,
				createdAt,
				status,
				searchText: [title, artistId, String(t.id)].filter(Boolean).join(' | '),
			}
		})
	}, [props.tracks])

	async function patchTrack(id: string, payload: { action: 'approve' | 'take_down' | 'restore'; reason?: string }) {
		const res = await fetch('/api/admin/tracks', {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ id, ...payload }),
		})
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function runConfirmedAction(reason: string) {
		if (!confirm) return
		if (loadingId) return
		setError(null)
		setLoadingId(confirm.id)
		try {
			await patchTrack(confirm.id, { action: confirm.action, reason: reason.trim() || undefined })
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update track')
		} finally {
			setLoadingId(null)
		}
	}

	const activeClass = 'bg-white/5'

	return (
		<div>
			<div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
				<div>
					<h1 className="text-2xl font-bold">Tracks</h1>
					<p className="mt-1 text-sm text-gray-400">Review uploads and moderate tracks (approve, take down, restore).</p>
					{error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
				</div>

				<div className="flex flex-wrap gap-2">
					<Link
						href="/admin/tracks/pending"
						className={`inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 ${props.filter === 'pending' ? activeClass : ''}`}
					>
						Pending
					</Link>
					<Link
						href="/admin/tracks/live"
						className={`inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 ${props.filter === 'live' ? activeClass : ''}`}
					>
						Live
					</Link>
					<Link
						href="/admin/tracks/removed"
						className={`inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 ${props.filter === 'removed' ? activeClass : ''}`}
					>
						Removed
					</Link>
					<Link
						href="/admin/tracks/upload"
						className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5"
					>
						Upload
					</Link>
				</div>
			</div>

			<DataTable
				rows={rows}
				rowIdKey="id"
				searchPlaceholder="Search by title, artist id, track id…"
				emptyMessage={`No ${labelFilter(props.filter).toLowerCase()} tracks found.`}
				pageSize={25}
				initialSort={{ columnId: 'created', dir: 'desc' }}
				filters={[
					{
						id: 'status',
						label: 'Status',
						options: [
							{ value: 'pending', label: 'Pending' },
							{ value: 'live', label: 'Live' },
							{ value: 'removed', label: 'Removed' },
						],
						getValue: (r) => r.status,
					},
				]}
				columns={[
					{
						id: 'title',
						header: 'Title',
						accessor: 'searchText',
						sortValue: (r) => r.title,
						render: (r) => (
							<div className="min-w-0">
								<div className="truncate font-medium">{r.title || '—'}</div>
								<div className="mt-1 truncate text-xs text-gray-400">{r.id}</div>
							</div>
						),
					},
					{
						id: 'artist',
						header: 'Artist',
						accessor: 'artistId',
						sortValue: (r) => r.artistId ?? '',
						render: (r) => <span className="text-sm break-all">{r.artistId ?? '—'}</span>,
					},
					{
						id: 'approved',
						header: 'Approved',
						accessor: 'approved',
						sortValue: (r) => (r.approved ? 1 : 0),
						render: (r) => (
							<span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${r.approved ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200' : 'border-amber-500/30 bg-amber-500/10 text-amber-200'}`}>
								{r.approved ? 'Yes' : 'No'}
							</span>
						),
					},
					{
						id: 'active',
						header: 'Active',
						accessor: 'isActive',
						sortValue: (r) => (r.isActive ? 1 : 0),
						render: (r) => (
							<span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${r.isActive ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200' : 'border-red-500/30 bg-red-500/10 text-red-200'}`}>
								{r.isActive ? 'Yes' : 'No'}
							</span>
						),
					},
					{
						id: 'created',
						header: 'Created',
						accessor: 'createdAt',
						sortValue: (r) => (r.createdAt ? new Date(r.createdAt) : null),
						render: (r) => formatDate(r.createdAt),
					},
					{
						id: 'actions',
						header: 'Actions',
						render: (r) => {
							const busy = loadingId === r.id
							const showApprove = !r.approved
							const showTakeDown = r.approved && r.isActive
							const showRestore = r.approved && !r.isActive

							return (
								<div className="flex flex-wrap justify-end gap-2">
									{showApprove ? (
										<button
											disabled={busy}
											className="inline-flex h-9 items-center rounded-xl bg-white/10 px-3 text-sm hover:bg-white/15 disabled:opacity-60"
											onClick={() =>
												setConfirm({
													id: r.id,
													action: 'approve',
													title: 'Approve track?',
													description: 'This marks the track as approved so it can be shown to users.',
													tone: 'primary',
												})
											}
										>
											Approve
										</button>
									) : null}
									{showTakeDown ? (
										<button
											disabled={busy}
											className="inline-flex h-9 items-center rounded-xl bg-red-600 px-3 text-sm text-white hover:bg-red-500 disabled:opacity-60"
											onClick={() =>
												setConfirm({
													id: r.id,
													action: 'take_down',
													title: 'Take down track?',
													description: 'This removes the track from being active/live without deleting it.',
													tone: 'danger',
												})
											}
										>
											Take down
										</button>
									) : null}
									{showRestore ? (
										<button
											disabled={busy}
											className="inline-flex h-9 items-center rounded-xl bg-white/10 px-3 text-sm hover:bg-white/15 disabled:opacity-60"
											onClick={() =>
												setConfirm({
													id: r.id,
													action: 'restore',
													title: 'Restore track?',
													description: 'This marks the track active again.',
													tone: 'primary',
												})
											}
										>
											Restore
										</button>
									) : null}
								</div>
							)
						},
					},
				]}
			/>

			<ConfirmDialog
				open={!!confirm}
				title={confirm?.title ?? ''}
				description={confirm?.description ?? ''}
				confirmText={confirm?.tone === 'danger' ? 'Confirm' : 'Apply'}
				confirmTone={confirm?.tone ?? 'primary'}
				busy={!!loadingId}
				onCancelAction={() => setConfirm(null)}
				onConfirmAction={async ({ reason }) => {
					const current = confirm
					setConfirm(null)
					if (!current) return
					await runConfirmedAction(reason)
				}}
			/>
		</div>
	)
}
