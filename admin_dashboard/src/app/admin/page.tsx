import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export default async function AdminIndexPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	// Let the admin layout / RBAC checks run on a real page route.
	redirect('/admin/dashboard')
}
