"use server"

import { getSupabaseAdmin, getSupabaseAdminStrict } from "@/lib/supabase-admin"
import { revalidatePath } from "next/cache"

export type AdminArtist = {
	id: string
	stage_name: string | null
	approved: boolean
	status: string | null
	blocked: boolean
	songs_count: number
	videos_count: number
	created_at: string
	firebase_uid: string | null
	user_id: string | null
}

export async function getArtists(): Promise<AdminArtist[]> {
	const supabaseAdmin = getSupabaseAdmin()
	// NOTE: songs_count/videos_count columns don't exist yet in the DB.
	// For now we compute counts safely from songs/videos tables and keep the UI shape stable.
	let data: any[] | null = null
	let error: any = null
	// Try richer schema first.
	;({ data, error } = await supabaseAdmin
		.from('artists')
		.select('id, stage_name, approved, status, blocked, created_at, firebase_uid, user_id')
		.order('created_at', { ascending: false })
		.limit(100))
	if (error) {
		// Fallback to minimal schema.
		;({ data, error } = await supabaseAdmin
			.from('artists')
			.select('id, stage_name, approved, created_at, firebase_uid, user_id')
			.order('created_at', { ascending: false })
			.limit(100))
	}
	if (error) throw error

	const artists = (data ?? []) as Array<{
		id: string
		stage_name: string | null
		approved: boolean | null
		status?: string | null
		blocked?: boolean | null
		created_at: string
		firebase_uid: string | null
		user_id: string | null
	}>

	const rows = await Promise.all(
		artists.map(async (a) => {
			let songsCount = 0
			try {
				if (a.firebase_uid) {
					const { count } = await supabaseAdmin
						.from("songs")
						.select("id", { head: true, count: "exact" })
						.eq("firebase_uid", a.firebase_uid)
					songsCount = count ?? 0
				} else if (a.user_id) {
					const { count } = await supabaseAdmin
						.from("songs")
						.select("id", { head: true, count: "exact" })
						.eq("user_id", a.user_id)
					songsCount = count ?? 0
				} else {
					const { count } = await supabaseAdmin
						.from("songs")
						.select("id", { head: true, count: "exact" })
						.eq("artist_id", a.id)
					songsCount = count ?? 0
				}
			} catch {
				songsCount = 0
			}

			let videosCount = 0
			try {
				if (a.firebase_uid) {
					const { count } = await supabaseAdmin
						.from("videos")
						.select("id", { head: true, count: "exact" })
						.eq("firebase_uid", a.firebase_uid)
					videosCount = count ?? 0
				} else if (a.user_id) {
					const { count } = await supabaseAdmin
						.from("videos")
						.select("id", { head: true, count: "exact" })
						.eq("user_id", a.user_id)
					videosCount = count ?? 0
				}
			} catch {
				videosCount = 0
			}

			return {
				id: a.id,
				stage_name: a.stage_name,
				approved: a.approved === true,
				status: a.status ?? (a.approved === true ? 'active' : 'pending'),
				blocked: a.blocked === true,
				songs_count: songsCount,
				videos_count: videosCount,
				created_at: a.created_at,
				firebase_uid: a.firebase_uid,
				user_id: a.user_id,
			} satisfies AdminArtist
		}),
	)

	return rows
}

export async function setArtistApproval(artistId: string, approved: boolean) {
	const supabaseAdmin = getSupabaseAdminStrict()
	const { error } = await supabaseAdmin
		.from("artists")
		.update({ approved })
		.eq("id", artistId)

	if (error) throw error
	revalidatePath("/admin/artists")
}
