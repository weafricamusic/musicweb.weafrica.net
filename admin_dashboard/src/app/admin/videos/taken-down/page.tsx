import { redirect } from 'next/navigation'

import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

import { VideosTable, type VideoRow } from '../VideosTable'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export default async function AdminVideosTakenDownPage() {
	const firebaseUser = await verifyFirebaseSessionCookie()
	if (!firebaseUser) redirect('/auth/login')

	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		redirect('/admin/dashboard')
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for videos" />

	let videos: VideoRow[] = []
	let loadError: string | null = null
	try {
		const { data, error } = await supabase
			.from('videos')
			.select('*')
			.eq('is_active', false)
			.order('created_at', { ascending: false })
			.limit(200)
		if (error) loadError = error.message
		videos = (data ?? []) as VideoRow[]
	} catch (e) {
		loadError = e instanceof Error ? e.message : 'Failed to load videos'
		videos = []
	}

	return (
		<div className="space-y-4">
			{loadError ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					<div className="font-medium">Video list unavailable</div>
					<div className="mt-1 opacity-90">{loadError}</div>
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<VideosTable videos={videos} filter="taken_down" />
			</div>
		</div>
	)
}
