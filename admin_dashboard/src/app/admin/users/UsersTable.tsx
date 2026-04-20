'use client'

import { useRouter } from 'next/navigation'
import { useMemo, useState } from 'react'
import Link from 'next/link'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import type { AdminUsersRow, AdminUserRole, AdminUserStatus } from './actions'

type ConfirmState =
	| null
	| {
			uid: string
			action: 'set_role' | 'set_status'
			payload: { role?: AdminUserRole; status?: AdminUserStatus }
			title: string
			description: string
			tone: 'primary' | 'danger'
	  }

function labelRole(role: AdminUserRole): string {
	if (role === 'consumer') return 'Consumer'
	if (role === 'artist') return 'Artist'
	if (role === 'dj') return 'DJ'
	return 'Admin'
}

function labelStatus(status: AdminUserStatus): string {
	if (status === 'pending') return 'Pending'
	if (status === 'active') return 'Active'
	if (status === 'suspended') return 'Suspended'
	return 'Banned'
}

export function UsersTable({ users, canManageFinance }: { users: AdminUsersRow[]; canManageFinance?: boolean }) {
	const router = useRouter()
	const [loadingUid, setLoadingUid] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<ConfirmState>(null)

	const rows = useMemo(() => {
		return users.map((u) => ({
			...u,
			searchText: [u.name, u.email, u.uid, u.role, u.status].filter(Boolean).join(' | '),
		}))
	}, [users])

	async function patchUser(uid: string, body: unknown) {
		const res = await fetch(`/api/admin/users/${encodeURIComponent(uid)}`, {
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
		if (loadingUid) return
		setError(null)
		setLoadingUid(confirm.uid)
		try {
			if (confirm.action === 'set_role') {
				await patchUser(confirm.uid, { action: 'set_role', role: confirm.payload.role })
			}
			if (confirm.action === 'set_status') {
				await patchUser(confirm.uid, { action: 'set_status', status: confirm.payload.status, reason })
			}
			router.refresh()
		} catch (err) {
			setError(err instanceof Error ? err.message : 'Failed to update user')
		} finally {
			setLoadingUid(null)
		}
	}

	return (
		<div>
			<div className="mb-4">
				<h1 className="text-2xl font-bold">Users</h1>
				<p className="mt-1 text-sm text-gray-400">Manage roles and access status across Consumers, Artists, and DJs.</p>
				{error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
			</div>

			<DataTable
				rows={rows}
				rowIdKey="uid"
				searchPlaceholder="Search by name, email, uid…"
				emptyMessage="No users found."
				pageSize={25}
				initialSort={{ columnId: 'created', dir: 'desc' }}
				filters={[
					{
						id: 'role',
						label: 'Role',
						options: [
							{ value: 'consumer', label: 'Consumer' },
							{ value: 'artist', label: 'Artist' },
							{ value: 'dj', label: 'DJ' },
							{ value: 'admin', label: 'Admin' },
						],
						getValue: (r) => r.role,
					},
					{
						id: 'status',
						label: 'Status',
						options: [
							{ value: 'pending', label: 'Pending' },
							{ value: 'active', label: 'Active' },
							{ value: 'suspended', label: 'Suspended' },
							{ value: 'banned', label: 'Banned' },
						],
						getValue: (r) => r.status,
					},
				]}
				columns={[
					{
						id: 'name',
						header: 'Name',
						accessor: 'searchText',
						sortValue: (r) => r.name,
						render: (r) => (
							<div className="min-w-0">
								<div className="truncate font-medium">{r.name || '—'}</div>
								<div className="mt-1 truncate text-xs text-gray-400">{r.uid}</div>
							</div>
						),
					},
					{
						id: 'email',
						header: 'Email',
						accessor: 'email',
						sortValue: (r) => r.email ?? '',
						render: (r) => <span className="text-sm break-all">{r.email ?? '—'}</span>,
					},
					{
						id: 'role',
						header: 'Role',
						accessor: 'role',
						sortValue: (r) => r.role,
						render: (r) => (
							<select
								disabled={loadingUid === r.uid || r.role === 'admin'}
								className="h-9 rounded-xl border border-white/10 bg-black/20 px-3 text-sm disabled:opacity-60"
								value={r.role}
								onChange={(e) => {
									const next = e.target.value as AdminUserRole
									if (!next || next === r.role) return
									setConfirm({
										uid: r.uid,
										action: 'set_role',
										payload: { role: next },
										title: 'Change user role?',
										description: `Change role from ${labelRole(r.role)} to ${labelRole(next)}. This revokes tokens so the new dashboard applies immediately.`,
										tone: 'primary',
									})
								}}
							>
								<option value="consumer">Consumer</option>
								<option value="artist">Artist</option>
								<option value="dj">DJ</option>
								<option value="admin" disabled>
									Admin (managed via allowlist)
								</option>
							</select>
						),
					},
					{
						id: 'status',
						header: 'Status',
						accessor: 'status',
						sortValue: (r) => r.status,
						render: (r) => (
							<select
								disabled={loadingUid === r.uid || r.role === 'admin'}
								className="h-9 rounded-xl border border-white/10 bg-black/20 px-3 text-sm disabled:opacity-60"
								value={r.status}
								onChange={(e) => {
									const next = e.target.value as AdminUserStatus
									if (!next || next === r.status) return
									const isDanger = next === 'suspended' || next === 'banned'
									setConfirm({
										uid: r.uid,
										action: 'set_status',
										payload: { status: next },
										title: isDanger ? `Set status to ${labelStatus(next)}?` : 'Change user status? ',
										description: isDanger
										? 'This disables Firebase login and revokes tokens instantly. It also updates creator permissions and writes audit logs.'
										: `Set status to ${labelStatus(next)}.`,
										tone: isDanger ? 'danger' : 'primary',
									})
								}}
							>
								<option value="pending">Pending</option>
								<option value="active">Active</option>
								<option value="suspended">Suspended</option>
								<option value="banned">Banned</option>
							</select>
						),
					},
					{
						id: 'created',
						header: 'Created',
						accessor: 'createdAt',
						sortValue: (r) => (r.createdAt ? new Date(r.createdAt) : null),
						render: (r) => (r.createdAt ? new Date(r.createdAt).toLocaleString() : '—'),
					},
					{
						id: 'actions',
						header: 'Actions',
						render: (r) => (
							<div className="flex flex-wrap justify-end gap-2">
								<Link
									href={`/dashboard/users/${encodeURIComponent(r.uid)}`}
									className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5"
								>
									View
								</Link>
								{canManageFinance ? (
									<Link
										href={`/admin/subscriptions/user-subscriptions?q=${encodeURIComponent(r.uid)}`}
										className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-sm hover:bg-white/5"
									>
										Subscription
									</Link>
								) : null}
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
				busy={!!loadingUid}
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
