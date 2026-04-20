import { redirect } from 'next/navigation'
import { assertPermission, getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

export default async function FinancePage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		redirect('/dashboard')
	}

	// Legacy module lives under /admin/payments for now.
	redirect('/admin/payments')
}
