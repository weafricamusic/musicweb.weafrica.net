'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import Link from 'next/link'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'

type ArtistRow = {
	id: string | number
	name: string | null
	email: string | null
	phone?: string | null
	status: 'pending' | 'active' | 'blocked'
	verified: boolean
	region: string
	avatarUrl?: string | null
	songsCount: number
	videosCount: number
	uploads: number
	createdAt: string | null
}

function getContact(a: ArtistRow): string {
	return (a.email ?? a.phone ?? '—') as string
}

export function ArtistsTable({ artists, totalCount }: { artists: ArtistRow[]; totalCount?: number }) {
	const router = useRouter()
	const [loadingId, setLoadingId] = useState<string | number | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<
		| { kind: 'set_status'; id: string | number; status: ArtistRow['status'] }
		| { kind: 'set_verified'; id: string | number; verified: boolean }
		| null
	>(null)

	async function patchArtist(id: string | number, body: unknown) {
		const res = await fetch(`/api/admin/artists/${encodeURIComponent(String(id))}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body),
		})
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function setStatus(id: string | number, status: ArtistRow['status'], reason?: string) {
		if (loadingId !== null) return
		setError(null)
		setLoadingId(id)
		try {
			await patchArtist(id, { action: 'set_status', status, reason: (reason ?? '').trim() || undefined })
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update artist')
		} finally {
			setLoadingId(null)
		}
	}

	async function setVerified(id: string | number, verified: boolean, reason?: string) {
		if (loadingId !== null) return
		setError(null)
		setLoadingId(id)
		try {
			await patchArtist(id, { action: 'set_verified', verified, reason: (reason ?? '').trim() || undefined })
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update verification')
		} finally {
			setLoadingId(null)
		}
	}

	return (
		<div>
			<div className="mb-4">
				<h2 className="text-base font-semibold">Artists Management</h2>
				<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Manage all registered artists.</p>
				{typeof totalCount === 'number' ? (
					<p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">Total loaded: {totalCount}</p>
				) : null}
				{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}
			</div>

			<DataTable
				rows={artists}
				rowIdKey="id"
				searchPlaceholder="Search artists by name/email/phone…"
				emptyMessage="No artists found."
				pageSize={25}
				initialSort={{ columnId: 'newest', dir: 'desc' }}
				filters={[
					{
						id: 'status',
						label: 'Status',
						options: [
							{ value: 'pending', label: 'Pending' },
							{ value: 'active', label: 'Active' },
							{ value: 'blocked', label: 'Blocked' },
						],
						getValue: (row) => row.status,
					},
					{
						id: 'verified',
						label: 'Verified',
						options: [
							{ value: 'yes', label: 'Verified' },
							{ value: 'no', label: 'Not Verified' },
						],
						getValue: (row) => (row.verified ? 'yes' : 'no'),
					},
				]}
				columns={[
					{
						id: 'artist',
						header: 'Artist Name',
						accessor: 'name',
						sortValue: (a) => a.name ?? '',
						render: (a) => (
							<div className="flex items-center gap-3">
								{a.avatarUrl ? (
									<img
										alt=""
										src={a.avatarUrl ?? undefined}
										className="h-9 w-9 rounded-full border border-black/[.08] object-cover dark:border-white/[.145]"
									/>
								) : (
									<div className="h-9 w-9 rounded-full border border-black/[.08] bg-black/[.04] dark:border-white/[.145] dark:bg-white/[.06]" />
								)}
								<div className="min-w-0">
									<Link
										href={`/dashboard/artists/${encodeURIComponent(String(a.id))}`}
										className="block truncate font-medium hover:underline"
									>
										{a.name ?? '—'}
									</Link>
									<p className="truncate text-xs text-zinc-600 dark:text-zinc-400">{a.id}</p>
								</div>
							</div>
						),
					},
					{
						id: 'contact',
						header: 'Email / Phone',
						searchable: true,
						sortValue: (a) => getContact(a),
						render: (a) => <span className="text-sm">{getContact(a)}</span>,
					},
					{
						id: 'status',
						header: 'Status',
						searchable: false,
						sortValue: (a) => a.status,
						render: (a) => {
							if (a.status === 'active')
								return (
									<span className="rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300">
										Active
									</span>
								)
							if (a.status === 'blocked')
								return (
									<span className="rounded-full bg-red-50 px-2 py-1 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300">
										Blocked
									</span>
								)
							return (
								<span className="rounded-full bg-zinc-100 px-2 py-1 text-xs text-zinc-700 dark:bg-zinc-900/40 dark:text-zinc-300">
									Pending
								</span>
							)
						},
					},
					{
						id: 'verified',
						header: 'Verification',
						searchable: false,
						sortValue: (a) => (a.verified ? 1 : 0),
						render: (a) =>
							a.verified ? (
								<span className="rounded-full bg-sky-50 px-2 py-1 text-xs text-sky-700 dark:bg-sky-900/20 dark:text-sky-300">
									Verified
								</span>
							) : (
								<span className="rounded-full bg-black/[.04] px-2 py-1 text-xs text-zinc-700 dark:bg-white/[.06] dark:text-zinc-200">
									Not Verified
								</span>
							),
					},
					{
						id: 'uploads',
						header: 'Uploads',
						searchable: false,
						sortValue: (a) => a.uploads,
						render: (a) => (
							<span className="font-medium">
								{a.uploads} <span className="text-xs text-zinc-600 dark:text-zinc-400">({a.songsCount} songs / {a.videosCount} videos)</span>
							</span>
						),
					},
					{
						id: 'region',
						header: 'Region',
						searchable: false,
						sortValue: (a) => a.region,
						render: (a) => (
							<span className="rounded-full bg-black/[.04] px-2 py-1 text-xs text-zinc-700 dark:bg-white/[.06] dark:text-zinc-200">
								{a.region}
							</span>
						),
					},
					{
						id: 'newest',
						header: 'Newest',
						accessor: 'createdAt',
						searchable: false,
						sortValue: (r) => (r.createdAt ? new Date(r.createdAt) : null),
						render: (r) => (r.createdAt ? new Date(r.createdAt).toLocaleDateString() : '—'),
					},
					{
						id: 'actions',
						header: 'Actions',
						searchable: false,
						render: (r) => (
							<div className="flex flex-wrap gap-2">
								<Link
									href={`/dashboard/artists/${encodeURIComponent(String(r.id))}`}
									className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm dark:border-white/[.145]"
								>
									View
								</Link>
								{r.status === 'pending' ? (
									<button
										type="button"
										disabled={loadingId === r.id}
										onClick={() => setConfirm({ kind: 'set_status', id: r.id, status: 'active' })}
										className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
									>
										{loadingId === r.id ? 'Saving…' : 'Approve'}
									</button>
								) : null}
								{r.status !== 'blocked' ? (
									<button
										type="button"
										disabled={loadingId === r.id}
										onClick={() => setConfirm({ kind: 'set_status', id: r.id, status: 'blocked' })}
										className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm text-red-700 disabled:opacity-60 dark:border-white/[.145] dark:text-red-300"
									>
										{loadingId === r.id ? 'Saving…' : 'Block'}
									</button>
								) : (
									<button
										type="button"
										disabled={loadingId === r.id}
										onClick={() => setConfirm({ kind: 'set_status', id: r.id, status: 'pending' })}
										className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
									>
										{loadingId === r.id ? 'Saving…' : 'Unblock'}
									</button>
								)}
								<button
									type="button"
									disabled={loadingId === r.id}
									onClick={() => setConfirm({ kind: 'set_verified', id: r.id, verified: !r.verified })}
									className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm disabled:opacity-60 dark:border-white/[.145]"
								>
									{loadingId === r.id ? 'Saving…' : r.verified ? 'Unverify' : 'Verify'}
								</button>
							</div>
						),
					},
				]}
			/>

			<ConfirmDialog
				open={!!confirm}
				title={
					confirm?.kind === 'set_verified'
						? confirm.verified
							? 'Verify this artist?'
							: 'Remove verification?'
						: confirm?.status === 'active'
							? 'Approve this artist?'
							: confirm?.status === 'blocked'
								? 'Block this artist?'
								: 'Unblock this artist?'
				}
				description="This will update Supabase status/flags, enforce live restrictions (if applicable), and write an audit log."
				confirmText={
					confirm?.kind === 'set_verified'
						? confirm.verified
							? 'Verify'
							: 'Unverify'
						: confirm?.status === 'active'
							? 'Approve'
							: confirm?.status === 'blocked'
								? 'Block'
								: 'Unblock'
				}
				confirmTone={confirm?.kind === 'set_status' && confirm.status === 'blocked' ? 'danger' : 'primary'}
				busy={loadingId !== null}
				onCancelAction={() => setConfirm(null)}
				onConfirmAction={async ({ reason }) => {
					if (!confirm) return
					const c = confirm
					setConfirm(null)
					if (c.kind === 'set_status') await setStatus(c.id, c.status, reason)
					if (c.kind === 'set_verified') await setVerified(c.id, c.verified, reason)
				}}
			/>
		</div>
	)
}
