'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'

import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'

export type VideoRow = {
	id: string
	title?: string | null
	caption?: string | null
	description?: string | null
	artist_id?: string | null
	artistId?: string | null
	approved?: boolean | null
	is_active?: boolean | null
	isActive?: boolean | null
	created_at?: string | null
	createdAt?: string | null
	[key: string]: unknown
}

type VideoFilter = 'pending' | 'live' | 'taken_down'

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
	status: VideoFilter
	searchText: string
}

function normalizeVideoTitle(v: VideoRow): string {
	const candidates = [v.title, v.caption, v.description, v['video_title']]
	for (const c of candidates) {
		if (typeof c === 'string') {
			const value = c.trim()
			if (value) return value
		}
	}
	return String(v.id)
}

function normalizeArtistId(v: VideoRow): string | null {
	const candidates = [v.artist_id, v.artistId, v['artist_uuid'], v['creator_id']]
	for (const c of candidates) {
		if (typeof c === 'string') {
			const value = c.trim()
			if (value) return value
		}
	}
	return null
}

function normalizeApproved(v: VideoRow): boolean {
	return v.approved === true
}

function normalizeIsActive(v: VideoRow): boolean {
	if (v.is_active === false || v.isActive === false) return false
	return true
}

function normalizeCreatedAt(v: VideoRow): string | null {
	const raw = v.created_at ?? v.createdAt
	if (typeof raw === 'string') return raw
	return null
}

function statusFor(v: VideoRow): VideoFilter {
	const approved = normalizeApproved(v)
	const isActive = normalizeIsActive(v)
	if (!approved) return 'pending'
	if (!isActive) return 'taken_down'
	return 'live'
}

function labelFilter(filter: VideoFilter): string {
	if (filter === 'pending') return 'Pending'
	if (filter === 'live') return 'Live'
	return 'Taken down'
}

function formatDate(value: string | null): string {
	if (!value) return '—'
	const d = new Date(value)
	if (Number.isNaN(d.getTime())) return '—'
	return d.toLocaleString()
}

export function VideosTable(props: { videos: VideoRow[]; filter: VideoFilter }) {
	const router = useRouter()
	const [loadingId, setLoadingId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<ConfirmState>(null)

	const rows = useMemo<TableRow[]>(() => {
		return (props.videos ?? []).map((v) => {
			const title = normalizeVideoTitle(v)
			const artistId = normalizeArtistId(v)
			const approved = normalizeApproved(v)
			const isActive = normalizeIsActive(v)
			const createdAt = normalizeCreatedAt(v)
			const status = statusFor(v)
			return {
				id: String(v.id),
				title,
				artistId,
				approved,
				isActive,
				createdAt,
				status,
				searchText: [title, artistId, String(v.id)].filter(Boolean).join(' | '),
			}
		})
	}, [props.videos])

	async function patchVideo(id: string, payload: { action: 'approve' | 'take_down' | 'restore'; reason?: string }) {
		const res = await fetch('/api/admin/videos', {
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
			await patchVideo(confirm.id, { action: confirm.action, reason: reason.trim() || undefined })
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update video')
		} finally {
			setLoadingId(null)
		}
	}

	const activeClass = 'bg-white/5'

	return (
		<div>
			<div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
				<div>
					<h1 className="text-2xl font-bold">Videos</h1>
					<p className="mt-1 text-sm text-gray-400">Moderate video uploads (approve, take down, restore).</p>
					{error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
				</div>

				<div className="flex flex-wrap gap-2">
					<Link
						href="/admin/videos/pending"
						className={`inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 ${props.filter === 'pending' ? activeClass : ''}`}
					>
						Pending
					</Link>
					<Link
						href="/admin/videos/live"
						className={`inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 ${props.filter === 'live' ? activeClass : ''}`}
					>
						Live
					</Link>
					<Link
						href="/admin/videos/taken-down"
						className={`inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 ${props.filter === 'taken_down' ? activeClass : ''}`}
					>
						Taken down
					</Link>
				</div>
			</div>

			<DataTable
				rows={rows}
				rowIdKey="id"
				searchPlaceholder="Search by title, artist id, video id…"
				emptyMessage={`No ${labelFilter(props.filter).toLowerCase()} videos found.`}
				pageSize={25}
				initialSort={{ columnId: 'created', dir: 'desc' }}
				filters={[
					{
						id: 'status',
						label: 'Status',
						options: [
							{ value: 'pending', label: 'Pending' },
							{ value: 'live', label: 'Live' },
							{ value: 'taken_down', label: 'Taken down' },
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
													title: 'Approve video?',
													description: 'This marks the video as approved so it can be shown to users.',
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
													title: 'Take down video?',
													description: 'This removes the video from being active/live without deleting it.',
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
													title: 'Restore video?',
													description: 'This marks the video active again.',
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
