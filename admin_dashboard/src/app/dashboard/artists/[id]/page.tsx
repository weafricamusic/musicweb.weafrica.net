import Link from 'next/link'
import { redirect } from 'next/navigation'

import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { DashboardShell } from '@/components/DashboardShell'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { ArtistDetailTabs } from './ArtistDetailTabs'

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

async function safeListBy<T extends Record<string, any>>(
	supabase: ReturnType<typeof createSupabaseServerClient>,
	table: string,
	where: Array<{ col: string; value: string }> | null,
) {
	try {
		if (!where?.length) return [] as T[]
		let query = supabase.from(table).select('*').order('created_at', { ascending: false }).limit(25)
		for (const w of where) query = query.eq(w.col, w.value)
		const { data, error } = await query
		if (error) return [] as T[]
		return (data ?? []) as T[]
	} catch {
		return [] as T[]
	}
}

export default async function ArtistDetailPage({ params }: { params: Promise<{ id: string }> }) {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const { id } = await params
	if (!id) redirect('/dashboard/artists')

	const supabase = createSupabaseServerClient()
	const { data: artist, error } = await supabase
		.from('artists')
		.select('*')
		.eq('id', id)
		.maybeSingle<ArtistRow>()

	if (error || !artist) {
		return (
			<DashboardShell title="Artist">
				<p className="text-sm text-red-600 dark:text-red-400">
					Error loading artist: {error?.message ?? 'Not found'}
				</p>
			</DashboardShell>
		)
	}

	const displayName = getDisplayName(artist)
	const avatarUrl = getAvatarUrl(artist)
	const status = normalizeStatus(artist)
	const verified = artist.verified === true

	let songsCount = 0
	try {
		if (artist.firebase_uid) {
			const { count } = await supabase
				.from('songs')
				.select('id', { head: true, count: 'exact' })
				.eq('firebase_uid', artist.firebase_uid)
			songsCount = count ?? 0
		}
		if (songsCount === 0 && artist.user_id) {
			const { count } = await supabase
				.from('songs')
				.select('id', { head: true, count: 'exact' })
				.eq('user_id', artist.user_id)
			songsCount = count ?? 0
		}
		if (songsCount === 0) {
			const { count } = await supabase
				.from('songs')
				.select('id', { head: true, count: 'exact' })
				.eq('artist_id', artist.id)
			songsCount = count ?? 0
		}
	} catch {
		songsCount = 0
	}

	let videosCount = 0
	try {
		if (artist.firebase_uid) {
			const { count } = await supabase
				.from('videos')
				.select('id', { head: true, count: 'exact' })
				.eq('firebase_uid', artist.firebase_uid)
			videosCount = count ?? 0
		}
		if (videosCount === 0 && artist.user_id) {
			const { count } = await supabase
				.from('videos')
				.select('id', { head: true, count: 'exact' })
				.eq('user_id', artist.user_id)
			videosCount = count ?? 0
		}
	} catch {
		videosCount = 0
	}

	const songs = await safeListBy(supabase, 'songs',
		artist.firebase_uid
			? [{ col: 'firebase_uid', value: String(artist.firebase_uid) }]
			: artist.user_id
				? [{ col: 'user_id', value: String(artist.user_id) }]
				: [{ col: 'artist_id', value: String(artist.id) }],
	)

	const videos = await safeListBy(supabase, 'videos',
		artist.firebase_uid
			? [{ col: 'firebase_uid', value: String(artist.firebase_uid) }]
			: artist.user_id
				? [{ col: 'user_id', value: String(artist.user_id) }]
				: null,
	)

	return (
		<DashboardShell title="Artist">
			<div className="grid gap-6">
				<div className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<div className="flex items-start justify-between gap-4">
						<div>
							<p className="text-sm text-zinc-600 dark:text-zinc-400">Artist</p>
							<div className="mt-1 flex flex-wrap items-center gap-2">
								{avatarUrl ? (
									<img
										alt=""
										src={avatarUrl ?? undefined}
										className="h-10 w-10 rounded-full border border-black/[.08] object-cover dark:border-white/[.145]"
									/>
								) : null}
								<h2 className="text-lg font-semibold">{displayName}</h2>
								{status === 'active' ? (
									<span className="rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300">
										Active
									</span>
								) : status === 'blocked' ? (
									<span className="rounded-full bg-red-50 px-2 py-1 text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300">
										Blocked
									</span>
								) : (
									<span className="rounded-full bg-zinc-100 px-2 py-1 text-xs text-zinc-700 dark:bg-zinc-900/40 dark:text-zinc-300">
										Pending
									</span>
								)}
								{verified ? (
									<span className="rounded-full bg-sky-50 px-2 py-1 text-xs text-sky-700 dark:bg-sky-900/20 dark:text-sky-300">
										Verified
									</span>
								) : null}
							</div>
							<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">ID: {artist.id}</p>
						</div>
						<Link
							href="/dashboard/artists"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							Back
						</Link>
					</div>

					<div className="mt-4 grid gap-3 text-sm md:grid-cols-2">
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Email</p>
							<p className="mt-1">{artist.email ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Phone</p>
							<p className="mt-1">{artist.phone ?? '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Joined</p>
							<p className="mt-1">{artist.created_at ? new Date(artist.created_at).toLocaleString() : '—'}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Songs</p>
							<p className="mt-1">{songsCount}</p>
						</div>
						<div>
							<p className="text-zinc-600 dark:text-zinc-400">Videos</p>
							<p className="mt-1">{videosCount}</p>
						</div>
					</div>
				</div>

				<ArtistDetailTabs artist={artist} songs={songs} videos={videos} />
			</div>
		</DashboardShell>
	)
}
