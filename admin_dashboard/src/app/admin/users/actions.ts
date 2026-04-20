"use server"

import { adminBackendFetchJson } from '@/lib/admin/backend'

export type AdminUserRole = 'consumer' | 'artist' | 'dj' | 'admin'
export type AdminUserStatus = 'pending' | 'active' | 'suspended' | 'banned'

export type AdminUsersRow = {
	uid: string
	name: string
	email: string | null
	role: AdminUserRole
	status: AdminUserStatus
	disabled: boolean
	createdAt: string | null
}

type BackendUserRow = {
	id?: string | null
	email?: string | null
	username?: string | null
	display_name?: string | null
	full_name?: string | null
	role?: string | null
	status?: string | null
	created_at?: string | null
	is_admin?: boolean | null
	admin_role?: string | null
}

function normalizeRole(raw: unknown): AdminUserRole | null {
	const v = String(raw ?? '').trim().toLowerCase()
	if (!v) return null
	if (v === 'user' || v === 'consumer' || v === 'listener') return 'consumer'
	if (v === 'artist') return 'artist'
	if (v === 'dj') return 'dj'
	if (v === 'admin' || v === 'super_admin') return 'admin'
	return null
}

function normalizeStatus(raw: unknown): AdminUserStatus | null {
	const v = String(raw ?? '').trim().toLowerCase()
	if (!v) return null
	if (v === 'pending') return 'pending'
	if (v === 'active') return 'active'
	if (v === 'blocked' || v === 'suspended') return 'suspended'
	if (v === 'banned') return 'banned'
	return null
}

export async function getUsers() {
	const users = await adminBackendFetchJson<BackendUserRow[]>('/admin/users?limit=250')

	return (Array.isArray(users) ? users : []).map((user) => {
		const role = user.is_admin ? 'admin' : (normalizeRole(user.role) ?? 'consumer')
		const status = normalizeStatus(user.status) ?? 'active'
		const uid = String(user.id ?? '').trim()
		const name =
			(user.display_name?.trim() || null) ??
			(user.full_name?.trim() || null) ??
			(user.username?.trim() || null) ??
			(user.email?.trim() || null) ??
			uid

		return {
			uid,
			name,
			email: user.email ?? null,
			role,
			status,
			disabled: status === 'suspended' || status === 'banned',
			createdAt: user.created_at ?? null,
		} satisfies AdminUsersRow
	})
}
