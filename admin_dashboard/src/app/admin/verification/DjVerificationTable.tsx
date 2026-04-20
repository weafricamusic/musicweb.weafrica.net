'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import type { DjVerificationRow } from './actions'

type ConfirmState =
	| null
	| {
			id: string
			action: 'set_status'
			payload: { status: 'pending' | 'active' | 'blocked' }
			title: string
			description: string
			tone: 'primary' | 'danger'
	  }

function labelBucket(status: 'pending' | 'active' | 'blocked'): string {
	if (status === 'active') return 'Approved'
	if (status === 'blocked') return 'Rejected'
	return 'Pending'
}

export function DjVerificationTable({ rows }: { rows: DjVerificationRow[] }) {
	const router = useRouter()
	const [loadingId, setLoadingId] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<ConfirmState>(null)

	const tableRows = useMemo(() => {
		return rows.map((r) => ({
			...r,
			searchText: [r.dj_name, r.id, r.status].filter(Boolean).join(' | '),
		}))
	}, [rows])

	async function patchDj(id: string, body: unknown) {
		const res = await fetch(`/api/admin/djs/${encodeURIComponent(id)}`, {
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
			await patchDj(confirm.id, { action: 'set_status', status: confirm.payload.status, reason })
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update DJ')
		} finally {
			setLoadingId(null)
		}
	}

	return (
		<div>
			<div className="mb-4">
				<h1 className="text-2xl font-bold">DJ verification</h1>
				<p className="mt-1 text-sm text-gray-400">Review and approve or reject DJ accounts. No payments.</p>
				{error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
			</div>

			<DataTable
				rows={tableRows}
				rowIdKey="id"
				searchPlaceholder="Search by name or id…"
				emptyMessage="No DJs found."
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
				]}
				columns={[
					{
						id: 'name',
						header: 'DJ',
						accessor: 'searchText',
						sortValue: (r) => r.dj_name ?? '',
						render: (r) => (
							<div className="min-w-0">
								<div className="truncate font-medium">{r.dj_name || '—'}</div>
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
											title: 'Approve DJ?',
											description: 'Sets status to Active and enables go-live permissions.',
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
											description: 'Sets status to Pending.',
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
											title: 'Reject DJ?',
											description: 'Sets status to Blocked and disables Firebase access (best-effort).',
											tone: 'danger',
										})
									}}
								>
									Reject
								</button>
								<Link
									href="/admin/djs"
									className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5"
								>
									DJs
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
