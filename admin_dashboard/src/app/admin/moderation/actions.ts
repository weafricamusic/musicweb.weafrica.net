"use server"

import { getSupabaseAdminStrict } from "@/lib/supabase-admin"
import { revalidatePath } from "next/cache"

export async function toggleSong(songId: string, active: boolean) {
	const supabaseAdmin = getSupabaseAdminStrict()
	const { error } = await supabaseAdmin
		.from("songs")
		.update({ is_active: active })
		.eq("id", songId)

	if (error) throw error
	revalidatePath("/admin/moderation")
}

export async function setSongApproved(songId: string, approved: boolean) {
	const supabaseAdmin = getSupabaseAdminStrict()
	const { error } = await supabaseAdmin
		.from('songs')
		.update({ approved })
		.eq('id', songId)

	if (error) throw error
	revalidatePath('/admin/moderation')
}

export async function toggleVideo(videoId: string, active: boolean) {
	const supabaseAdmin = getSupabaseAdminStrict()
	const { error } = await supabaseAdmin
		.from("videos")
		.update({ is_active: active })
		.eq("id", videoId)

	if (error) throw error
	revalidatePath("/admin/moderation")
}

export async function setVideoApproved(videoId: string, approved: boolean) {
	const supabaseAdmin = getSupabaseAdminStrict()
	const { error } = await supabaseAdmin
		.from('videos')
		.update({ approved })
		.eq('id', videoId)

	if (error) throw error
	revalidatePath('/admin/moderation')
}
