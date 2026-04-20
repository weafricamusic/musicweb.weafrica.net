import { redirect } from 'next/navigation'

import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

import UploadTrackClient from './UploadTrackClient'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type ArtistRow = {
	id: string
	stage_name?: string | null
	name?: string | null
	email?: string | null
	created_at?: string | null
}

function artistLabel(a: ArtistRow): string {
	const name = (a.stage_name ?? a.name ?? '').trim()
	if (name) return name
	if (a.email) return a.email
	return a.id
}

export default async function AdminUploadTrackPage() {
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
	if (!supabase) return <ServiceRoleRequired title="Service role required for uploads" />

	let artists: ArtistRow[] = []
	try {
		const { data } = await supabase
			.from('artists')
			.select('id,stage_name,name,email,created_at')
			.order('created_at', { ascending: false })
			.limit(250)
		artists = (data ?? []) as ArtistRow[]
	} catch {
		artists = []
	}

	const options = artists
		.map((a) => ({ id: String(a.id), label: artistLabel(a) }))
		.filter((a) => a.id && a.label)

	return (
		<div className="space-y-6">
			{options.length === 0 ? (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Upload Track</h1>
					<p className="mt-2 text-sm text-red-300">No artists found. Create/seed an artist first.</p>
				</div>
			) : (
				<UploadTrackClient artists={options} />
			)}
		</div>
	)
}
