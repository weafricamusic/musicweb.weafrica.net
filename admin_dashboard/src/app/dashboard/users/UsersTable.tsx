'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import Link from 'next/link'
import { DataTable } from '@/components/DataTable'
import { ConfirmDialog } from '@/components/ConfirmDialog'

type UserRow = {
	uid: string
	name: string
	email: string | null
	phone: string | null
	avatarUrl: string | null
	disabled: boolean
	status: 'active' | 'blocked'
	region: string
	joinedAt: string | null
	searchText: string
}

function getContact(u: UserRow): string {
	return (u.email ?? u.phone ?? '—') as string
}

export function UsersTable({ users, totalCount }: { users: UserRow[]; totalCount?: number }) {
	const router = useRouter()
	const [loadingUid, setLoadingUid] = useState<string | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [confirm, setConfirm] = useState<{ uid: string; nextDisabled: boolean } | null>(null)

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

	async function onToggleDisabled(uid: string, disabled: boolean, reason?: string) {
		if (loadingUid) return
		setError(null)
		setLoadingUid(uid)
		try {
			await patchUser(uid, { action: 'set_disabled', disabled, reason: (reason ?? '').trim() || undefined })
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
				<h2 className="text-base font-semibold">Users Management</h2>
				<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Manage all registered users.</p>
				{typeof totalCount === 'number' ? (
					<p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">Total loaded: {totalCount}</p>
				) : null}
				{error ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{error}</p> : null}
			</div>

			<DataTable
				rows={users}
				rowIdKey="uid"
				searchPlaceholder="Search users by username/email…"
				emptyMessage="No users found."
				pageSize={25}
				initialSort={{ columnId: 'joined', dir: 'desc' }}
				filters={[
					{
						id: 'status',
						label: 'Status',
						options: [
							{ value: 'active', label: 'Active' },
							{ value: 'blocked', label: 'Blocked' },
						],
						getValue: (row) => row.status,
					},
				]}
				columns={[
					{
						id: 'user',
						header: 'User',
						accessor: 'searchText',
						sortValue: (u) => u.name,
						render: (u) => (
							<div className="flex items-center gap-3">
								{u.avatarUrl ? (
									<img
										alt=""
										src={u.avatarUrl ?? undefined}
										className="h-9 w-9 rounded-full border border-black/[.08] object-cover dark:border-white/[.145]"
									/>
								) : (
									<div className="h-9 w-9 rounded-full border border-black/[.08] bg-black/[.04] dark:border-white/[.145] dark:bg-white/[.06]" />
								)}
								<div className="min-w-0">
									<Link href={`/dashboard/users/${encodeURIComponent(u.uid)}`} className="block truncate font-medium hover:underline">
										{u.name}
									</Link>
									<p className="truncate text-xs text-zinc-600 dark:text-zinc-400">{u.uid}</p>
								</div>
							</div>
						),
					},
					{
						id: 'contact',
						header: 'Email / Phone',
						accessor: 'email',
						searchable: true,
						sortValue: (u) => getContact(u),
						render: (u) => <span className="text-sm">{getContact(u)}</span>,
					},
					{
						id: 'status',
						header: 'Status',
						accessor: 'status',
						searchable: false,
						sortValue: (u) => (u.disabled ? 1 : 0),
						render: (u) =>
							u.disabled ? (
								<span className="rounded-full bg-red-50 px-2 py-1 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300">
									Blocked
								</span>
							) : (
								<span className="rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300">
									Active
								</span>
							),
					},
					{
						id: 'region',
						header: 'Region',
						accessor: 'region',
						searchable: false,
						sortValue: (u) => u.region,
						render: (u) => (
							<span className="rounded-full bg-black/[.04] px-2 py-1 text-xs text-zinc-700 dark:bg-white/[.06] dark:text-zinc-200">
								{u.region}
							</span>
						),
					},
					{
						id: 'joined',
						header: 'Joined',
						accessor: 'joinedAt',
						searchable: false,
						sortValue: (u) => (u.joinedAt ? new Date(u.joinedAt) : null),
						render: (u) => (u.joinedAt ? new Date(u.joinedAt).toLocaleDateString() : '—'),
					},
					{
						id: 'actions',
						header: 'Actions',
						searchable: false,
						render: (u) => (
							<div className="flex flex-wrap gap-2">
								<Link
									href={`/dashboard/users/${encodeURIComponent(u.uid)}`}
									className="inline-flex h-9 items-center rounded-xl border border-black/[.08] px-3 text-sm dark:border-white/[.145]"
								>
									View
								</Link>
								<button
									type="button"
									disabled={loadingUid === u.uid}
									onClick={() => setConfirm({ uid: u.uid, nextDisabled: !u.disabled })}
									className={`inline-flex h-9 items-center rounded-xl border px-3 text-sm disabled:opacity-60 dark:border-white/[.145] ${
										u.disabled ? 'border-black/[.08]' : 'border-black/[.08] text-red-700 dark:text-red-300'
									}`}
								>
									{loadingUid === u.uid ? 'Saving…' : u.disabled ? 'Unblock' : 'Block'}
								</button>
							</div>
						),
					},
				]}
			/>

			<ConfirmDialog
				open={!!confirm}
				title={confirm?.nextDisabled ? 'Block this user?' : 'Unblock this user?'}
				description={
					confirm?.nextDisabled
						? 'This immediately disables Firebase access and revokes refresh tokens. It also updates Supabase status and writes an audit log.'
						: 'This re-enables access and writes an audit log.'
				}
				confirmText={confirm?.nextDisabled ? 'Block user' : 'Unblock user'}
				confirmTone={confirm?.nextDisabled ? 'danger' : 'primary'}
				busy={!!loadingUid}
				onCancelAction={() => setConfirm(null)}
				onConfirmAction={async ({ reason }) => {
					if (!confirm) return
					const { uid, nextDisabled } = confirm
					setConfirm(null)
					await onToggleDisabled(uid, nextDisabled, reason)
				}}
			/>
		</div>
	)
}
