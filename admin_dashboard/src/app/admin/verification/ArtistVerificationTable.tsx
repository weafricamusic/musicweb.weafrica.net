'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import type { ArtistVerificationRow } from './actions'

type ConfirmState =
	| null
	| {
			id: string
			action: 'set_status' | 'set_verified'
			payload: { status?: 'pending' | 'active' | 'blocked'; verified?: boolean }
			title: string
			description: string
			tone: 'primary' | 'danger'
	  }

function labelBucket(status: 'pending' | 'active' | 'blocked'): string {
	if (status === 'active') return 'Approved'
	if (status === 'blocked') return 'Rejected'
	return 'Pending'
}

export function ArtistVerificationTable({ rows }: { rows: ArtistVerificationRow[] }) {
	const router = useRouter()
	const [loadingId, setLoadingId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<ConfirmState>(null)

	const tableRows = useMemo(() => {
		return rows.map((r) => ({
			...r,
			searchText: [r.stage_name, r.id, r.status, r.verified ? 'verified' : 'unverified'].filter(Boolean).join(' | '),
		}))
	}, [rows])

	async function patchArtist(id: string, body: unknown) {
		const res = await fetch(`/api/admin/artists/${encodeURIComponent(id)}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body),
		})
		if (res.ok) return
		const data = (await res.json().catch(() => null)) as { error?: string } | null
		throw new Error(data?.error || 'Request failed')
	}

	async function runConfirmedAction(reason?: string) {
		if (!confirm) return
		if (loadingId) return
		setError(null)
		setLoadingId(confirm.id)
		try {
			if (confirm.action === 'set_status') {
				await patchArtist(confirm.id, { action: 'set_status', status: confirm.payload.status, reason })
			}
			if (confirm.action === 'set_verified') {
				await patchArtist(confirm.id, { action: 'set_verified', verified: confirm.payload.verified, reason })
			}
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update artist')
		} finally {
			setLoadingId(null)
		}
	}

	return (
		<div>
			<div className="mb-4">
				<h1 className="text-2xl font-bold">Artist verification</h1>
				<p className="mt-1 text-sm text-gray-400">Review and approve or reject artist accounts. No payments.</p>
				{error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
			</div>

			<DataTable
				rows={tableRows}
				rowIdKey="id"
				searchPlaceholder="Search by stage name or id…"
				emptyMessage="No artists found."
				pageSize={25}
				initialSort={{ columnId: 'created', dir: 'desc' }}
				filters={[
					{
						id: 'status',
						label: 'Bucket',
						options: [
							{ value: 'pending', label: 'Pending' },
							{ value: 'active', label: 'Approved' },
							{ value: 'blocked', label: 'Rejected' },
						],
						getValue: (r) => r.status,
					},
					{
						id: 'verified',
						label: 'Verified',
						options: [
							{ value: 'yes', label: 'Verified' },
							{ value: 'no', label: 'Not verified' },
						],
						getValue: (r) => (r.verified ? 'yes' : 'no'),
					},
				]}
				columns={[
					{
						id: 'name',
						header: 'Artist',
						accessor: 'searchText',
						sortValue: (r) => r.stage_name ?? '',
						render: (r) => (
							<div className="min-w-0">
								<div className="truncate font-medium">{r.stage_name || '—'}</div>
								<div className="mt-1 truncate text-xs text-gray-400">{r.id}</div>
							</div>
						),
					},
					{
						id: 'bucket',
						header: 'Bucket',
						accessor: 'status',
						sortValue: (r) => r.status,
						render: (r) => <span className="text-sm">{labelBucket(r.status)}</span>,
					},
					{
						id: 'verifiedCol',
						header: 'Verified',
						render: (r) => (
							<span className={r.verified ? 'text-sm text-emerald-300' : 'text-sm text-gray-400'}>
								{r.verified ? 'Yes' : 'No'}
							</span>
						),
					},
					{
						id: 'created',
						header: 'Created',
						accessor: 'created_at',
						sortValue: (r) => new Date(r.created_at),
						render: (r) => (r.created_at ? new Date(r.created_at).toLocaleString() : '—'),
					},
					{
						id: 'actions',
						header: 'Actions',
						render: (r) => (
							<div className="flex flex-wrap justify-end gap-2">
								<button
									disabled={loadingId === r.id}
									className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 disabled:opacity-60"
									onClick={() => {
										setConfirm({
											id: r.id,
											action: 'set_status',
											payload: { status: 'active' },
											title: 'Approve artist?',
											description: 'Sets status to Active and enables creator permissions.',
											tone: 'primary',
										})
									}}
								>
									Approve
								</button>
								<button
									disabled={loadingId === r.id}
									className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 disabled:opacity-60"
									onClick={() => {
										setConfirm({
											id: r.id,
											action: 'set_status',
											payload: { status: 'pending' },
											title: 'Move back to pending?',
											description: 'Sets status to Pending and disables creator permissions.',
											tone: 'primary',
										})
									}}
								>
									Pending
								</button>
								<button
									disabled={loadingId === r.id}
									className="inline-flex h-9 items-center rounded-xl border border-red-500/30 bg-red-500/10 px-3 text-sm text-red-200 hover:bg-red-500/15 disabled:opacity-60"
									onClick={() => {
										setConfirm({
											id: r.id,
											action: 'set_status',
											payload: { status: 'blocked' },
											title: 'Reject artist?',
											description: 'Sets status to Blocked and disables Firebase access (best-effort).',
											tone: 'danger',
										})
									}}
								>
									Reject
								</button>
								<button
									disabled={loadingId === r.id}
									className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5 disabled:opacity-60"
									onClick={() => {
										setConfirm({
											id: r.id,
											action: 'set_verified',
											payload: { verified: !r.verified },
											title: r.verified ? 'Remove verification badge?' : 'Mark as verified?',
											description: 'Toggles the verified flag on the artist profile.',
											tone: 'primary',
										})
									}}
								>
									{r.verified ? 'Unverify' : 'Verify'}
								</button>
								<Link
									href="/admin/artists"
									className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5"
								>
									Artists
								</Link>
							</div>
						),
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
