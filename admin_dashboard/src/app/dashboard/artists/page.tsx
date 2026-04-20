import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { DashboardShell } from '@/components/DashboardShell'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { ArtistsTable } from './ArtistsTable'
export const runtime = 'nodejs'

type ArtistRow = {
	[key: string]: any
	id: string
	created_at?: string | null
	name?: string | null
	email?: string | null
	phone?: string | null
	stage_name?: string | null
	artist_name?: string | null
	display_name?: string | null
	full_name?: string | null
	username?: string | null
	firebase_uid?: string | null
	user_id?: string | null
	status?: string | null
	approved?: boolean | null
	blocked?: boolean | null
	verified?: boolean | null
	region?: string | null
	country?: string | null
	avatar_url?: string | null
	photo_url?: string | null
	profile_image_url?: string | null
}

type ArtistStatus = 'pending' | 'active' | 'blocked'

function normalizeStatus(a: ArtistRow): ArtistStatus {
	const raw = String(a.status ?? '').toLowerCase().trim()
	if (raw === 'blocked') return 'blocked'
	if (raw === 'active' || raw === 'approved') return 'active'
	if (raw === 'pending') return 'pending'
	if (a.blocked === true) return 'blocked'
	if (a.approved === true) return 'active'
	return 'pending'
}

function getAvatarUrl(a: ArtistRow): string | null {
	return (a.avatar_url ?? a.photo_url ?? a.profile_image_url ?? null) as string | null
}

function getDisplayName(a: ArtistRow): string {
	return (
		a.name ??
		a.stage_name ??
		a.artist_name ??
		a.display_name ??
		a.full_name ??
		a.username ??
		a.id ??
		'—'
	)
}

function getRegion(a: ArtistRow): string {
	const r = (a.region ?? a.country ?? 'MW') as string
	return r.toUpperCase() === 'MALAWI' ? 'MW' : r.toUpperCase()
}

export default async function ArtistsPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const supabase = createSupabaseServerClient()
	const { data: artists, error } = await supabase
		.from('artists')
		.select('*')
		.order('created_at', { ascending: false })
		.limit(100)

	if (error) {
		return (
			<DashboardShell title="Artists">
				<p className="text-sm text-red-600 dark:text-red-400">Error fetching artists: {error.message}</p>
			</DashboardShell>
		)
	}

	const rows = await Promise.all(
		(artists ?? []).map(async (a: ArtistRow) => {
			const name = getDisplayName(a)
			const email = (a.email ?? null) as string | null
			const phone = (a.phone ?? null) as string | null
			const createdAt = (a.created_at ?? null) as string | null
			const status = normalizeStatus(a)
			const verified = a.verified === true
			const region = getRegion(a)
			const avatarUrl = getAvatarUrl(a)

			// Songs: in this dataset, songs link most reliably by firebase_uid.
			// Fall back to user_id, then artist_id.
			let songsCount = 0
			try {
				if (a.firebase_uid) {
					const { count } = await supabase
						.from('songs')
						.select('id', { head: true, count: 'exact' })
						.eq('firebase_uid', a.firebase_uid)
					songsCount = count ?? 0
				}

				if (songsCount === 0 && a.user_id) {
					const { count } = await supabase
						.from('songs')
						.select('id', { head: true, count: 'exact' })
						.eq('user_id', a.user_id)
					songsCount = count ?? 0
				}

				if (songsCount === 0 && a.id != null) {
					const { count } = await supabase
						.from('songs')
						.select('id', { head: true, count: 'exact' })
						.eq('artist_id', a.id)
					songsCount = count ?? 0
				}
			} catch {
				songsCount = 0
			}

			// Videos: there is no artists->videos relationship in schema cache.
			// Prefer firebase_uid, then fall back to user_id.
			let videosCount = 0
			try {
				if (a.firebase_uid) {
					const { count } = await supabase
						.from('videos')
						.select('id', { head: true, count: 'exact' })
						.eq('firebase_uid', a.firebase_uid)
					videosCount = count ?? 0
				}

				if (videosCount === 0 && a.user_id) {
					const { count } = await supabase
						.from('videos')
						.select('id', { head: true, count: 'exact' })
						.eq('user_id', a.user_id)
					videosCount = count ?? 0
				}
			} catch {
				videosCount = 0
			}

			return {
				id: a.id,
				name,
				email,
				phone,
				status,
				verified,
				region,
				avatarUrl,
				songsCount,
				videosCount,
				uploads: songsCount + videosCount,
				createdAt,
			}
		}),
	)

	return (
		<DashboardShell title="Artists">
			<ArtistsTable artists={rows} totalCount={rows.length} />
		</DashboardShell>
	)
}
