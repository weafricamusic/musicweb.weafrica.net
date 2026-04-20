import { redirect } from 'next/navigation'
import { getAdminContext, hasPermission } from '@/lib/admin/session'
import type { AdminPermissions } from '@/lib/admin/types'

export async function requireAdmin(redirectTo: string = '/auth/login') {
	const ctx = await getAdminContext()
	if (!ctx) redirect(redirectTo)
	return ctx
}

export async function requirePermission(perm: keyof AdminPermissions, redirectTo: string = '/admin/dashboard') {
	const ctx = await getAdminContext()
	if (!ctx || !hasPermission(ctx, perm)) redirect(redirectTo)
	return ctx
}
