import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { DashboardShell } from '@/components/DashboardShell'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { DJsTable } from './DJsTable'
export const runtime = 'nodejs'

export default async function DJsPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const supabase = createSupabaseServerClient()
	const { data: djs, error } = await supabase.from('djs').select('*').order('created_at', { ascending: false }).limit(250)

	if (error) {
		return (
			<DashboardShell title="DJs">
				<p className="text-sm text-red-600 dark:text-red-400">Error fetching DJs: {error.message}</p>
			</DashboardShell>
		)
	}

	return (
		<DashboardShell title="DJs Management">
			<div className="mb-6">
				<h2 className="text-base font-semibold">DJs Management</h2>
				<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Manage all registered DJs.</p>
				<p className="mt-2 text-xs text-zinc-600 dark:text-zinc-400">Total loaded: {(djs ?? []).length}</p>
			</div>

			<DJsTable djs={(djs ?? []) as any} />
		</DashboardShell>
	)
}
