'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import Link from 'next/link'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'

type DjRow = {
	id: string
	dj_name: string | null
	approved?: boolean
	created_at?: string | null
	status?: string | null
	blocked?: boolean | null
	email?: string | null
	phone?: string | null
	region?: string | null
	country?: string | null
	avatar_url?: string | null
	photo_url?: string | null
	profile_image_url?: string | null
	uploads_count?: number | null
	mixes_count?: number | null
	songs_count?: number | null
	lives_count?: number | null
}

type DjStatus = 'pending' | 'active' | 'blocked'

function normalizeStatus(d: DjRow): DjStatus {
	const raw = (d.status ?? '').toLowerCase().trim()
	if (raw === 'blocked') return 'blocked'
	if (raw === 'active' || raw === 'approved') return 'active'
	if (raw === 'pending') return 'pending'
	if (d.blocked === true) return 'blocked'
	if (d.approved === true) return 'active'
	return 'pending'
}

function getAvatarUrl(d: DjRow): string | null {
	return d.avatar_url ?? d.photo_url ?? d.profile_image_url ?? null
}

function getContact(d: DjRow): string {
	return (d.email ?? d.phone ?? '—') as string
}

function getRegion(d: DjRow): string {
	const r = (d.region ?? d.country ?? 'MW') as string
	return r.toUpperCase() === 'MALAWI' ? 'MW' : r.toUpperCase()
}

function getUploads(d: DjRow): number {
	const uploads =
		(d.uploads_count ?? null) ??
		((d.mixes_count ?? 0) + (d.songs_count ?? 0) + (d.lives_count ?? 0))
	return typeof uploads === 'number' ? uploads : 0
}

export function DJsTable({ djs }: { djs: DjRow[] }) {
	const router = useRouter()
	const [loadingId, setLoadingId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<{ id: string; status: DjStatus } | null>(null)

	async function setStatus(djId: string, status: DjStatus, reason?: string) {
		if (loadingId) return
		setError(null)
		setLoadingId(djId)
		try {
			const res = await fetch(`/api/admin/djs/${encodeURIComponent(djId)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ action: 'set_status', status, reason: (reason ?? '').trim() || undefined }),
			})
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null
				throw new Error(body?.error || 'Failed to update approval')
			}
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update approval')
		} finally {
			setLoadingId(null)
		}
	}

	return (
		<div>
			<div className="mb-4">
				<h2 className="text-base font-semibold">DJs Management</h2>
				<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Approve or revoke DJ access.</p>
				{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}
			</div>

			<DataTable
				rows={djs}
				rowIdKey="id"
				searchPlaceholder="Search DJs by name/email/phone/id…"
				pageSize={25}
				initialSort={{ columnId: 'latest', dir: 'desc' }}
				filters={[
					{
						id: 'status',
						label: 'Status',
						options: [
							{ value: 'pending', label: 'Pending' },
							{ value: 'active', label: 'Active' },
							{ value: 'blocked', label: 'Blocked' },
						],
						getValue: (row) => normalizeStatus(row),
					},
				]}
				emptyMessage="No DJs found."
				columns={[
					{
						id: 'name',
						header: 'DJ Name',
						accessor: 'dj_name',
						sortValue: (d) => d.dj_name ?? '',
						render: (d) => (
							<div className="flex items-center gap-3">
								{getAvatarUrl(d) ? (
									<img
										alt=""
										src={getAvatarUrl(d) ?? undefined}
										className="h-9 w-9 rounded-full border border-black/[.08] object-cover dark:border-white/[.145]"
									/>
								) : (
									<div className="h-9 w-9 rounded-full border border-black/[.08] bg-black/[.04] dark:border-white/[.145] dark:bg-white/[.06]" />
								)}
								<div className="min-w-0">
									<Link
										href={`/dashboard/djs/${encodeURIComponent(d.id)}`}
										className="block truncate font-medium hover:underline"
									>
										{d.dj_name ?? '—'}
									</Link>
									<p className="truncate text-xs text-zinc-600 dark:text-zinc-400">{d.id}</p>
								</div>
							</div>
						),
					},
					{
						id: 'contact',
						header: 'Email / Phone',
						searchable: true,
						sortValue: (d) => getContact(d),
						render: (d) => <span className="text-sm">{getContact(d)}</span>,
					},
					{
						id: 'status',
						header: 'Status',
						searchable: false,
						sortValue: (d) => normalizeStatus(d),
						render: (d) => {
							const s = normalizeStatus(d)
							if (s === 'active') {
								return (
									<span className="rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300">
										Active
									</span>
								)
							}
							if (s === 'blocked') {
								return (
									<span className="rounded-full bg-red-50 px-2 py-1 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300">
										Blocked
									</span>
								)
							}
							return (
								<span className="rounded-full bg-zinc-100 px-2 py-1 text-xs text-zinc-700 dark:bg-zinc-900/40 dark:text-zinc-300">
									Pending
								</span>
							)
						},
					},
					{
						id: 'uploads',
						header: 'Uploads',
						searchable: false,
						sortValue: (d) => getUploads(d),
						render: (d) => <span className="font-medium">{getUploads(d)}</span>,
					},
					{
						id: 'region',
						header: 'Region',
						searchable: false,
						sortValue: (d) => getRegion(d),
						render: (d) => (
							<span className="rounded-full bg-black/[.04] px-2 py-1 text-xs text-zinc-700 dark:bg-white/[.06] dark:text-zinc-200">
								{getRegion(d)}
							</span>
						),
					},
					{
						id: 'latest',
						header: 'Latest',
						accessor: 'created_at',
						searchable: false,
						sortValue: (r) => (r.created_at ? new Date(r.created_at) : null),
						render: (r) => (r.created_at ? new Date(r.created_at).toLocaleDateString() : '—'),
					},
					{
						id: 'actions',
						header: 'Actions',
						searchable: false,
						render: (r) => (
							<div className="flex flex-wrap gap-2">
								<Link
									href={`/dashboard/djs/${encodeURIComponent(r.id)}`}
									className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm dark:border-white/[.145]"
								>
									View
								</Link>
								{normalizeStatus(r) === 'pending' ? (
									<button
										type="button"
										disabled={loadingId === r.id}
										onClick={() => setConfirm({ id: r.id, status: 'active' })}
										className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
									>
										{loadingId === r.id ? 'Saving…' : 'Approve'}
									</button>
								) : null}
								{normalizeStatus(r) !== 'blocked' ? (
									<button
										type="button"
										disabled={loadingId === r.id}
										onClick={() => setConfirm({ id: r.id, status: 'blocked' })}
										className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm text-red-700 disabled:opacity-60 dark:border-white/[.145] dark:text-red-300"
									>
										{loadingId === r.id ? 'Saving…' : 'Block'}
									</button>
								) : (
									<button
										type="button"
										disabled={loadingId === r.id}
										onClick={() => setConfirm({ id: r.id, status: 'pending' })}
										className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
									>
										{loadingId === r.id ? 'Saving…' : 'Unblock'}
									</button>
								)}
							</div>
						),
					},
				]}
			/>

			<ConfirmDialog
				open={!!confirm}
				title={
					confirm?.status === 'active'
						? 'Approve this DJ?'
						: confirm?.status === 'blocked'
							? 'Block this DJ?'
							: 'Unblock this DJ?'
				}
				description="This will update Supabase status, enforce live restrictions (if applicable), and write an audit log."
				confirmText={confirm?.status === 'active' ? 'Approve' : confirm?.status === 'blocked' ? 'Block' : 'Unblock'}
				confirmTone={confirm?.status === 'blocked' ? 'danger' : 'primary'}
				busy={!!loadingId}
				onCancelAction={() => setConfirm(null)}
				onConfirmAction={async ({ reason }) => {
					if (!confirm) return
					const { id, status } = confirm
					setConfirm(null)
					await setStatus(id, status, reason)
				}}
			/>
		</div>
	)
}
