"use server"

import { getSupabaseAdmin, getSupabaseAdminStrict } from "@/lib/supabase-admin"
import { revalidatePath } from "next/cache"

export type AdminDj = {
	id: string
	dj_name: string | null
	approved: boolean
	status: string | null
	blocked: boolean
	created_at: string
	firebase_uid: string | null
	user_id: string | null
}

export async function getDjs(): Promise<AdminDj[]> {
	const supabaseAdmin = getSupabaseAdmin()
	let data: any[] | null = null
	let error: any = null
	;({ data, error } = await supabaseAdmin
		.from('djs')
		.select('id, dj_name, approved, status, blocked, created_at, firebase_uid, user_id')
		.order('created_at', { ascending: false })
		.limit(100))
	if (error) {
		;({ data, error } = await supabaseAdmin
			.from('djs')
			.select('id, dj_name, approved, created_at')
			.order('created_at', { ascending: false })
			.limit(100))
	}
	if (error) throw error

	const rows = (data ?? []) as Array<{
		id: string
		dj_name: string | null
		approved: boolean | null
		status?: string | null
		blocked?: boolean | null
		created_at: string
		firebase_uid?: string | null
		user_id?: string | null
	}>
	return rows.map((d) => ({
		id: d.id,
		dj_name: d.dj_name ?? null,
		approved: d.approved === true,
		status: d.status ?? (d.approved === true ? 'active' : 'pending'),
		blocked: d.blocked === true,
		created_at: d.created_at,
		firebase_uid: d.firebase_uid ?? null,
		user_id: d.user_id ?? null,
	}))
}

export async function setDjApproval(djId: string, approved: boolean) {
	const supabaseAdmin = getSupabaseAdminStrict()
	const { error } = await supabaseAdmin
		.from("djs")
		.update({ approved })
		.eq("id", djId)

	if (error) throw error
	revalidatePath("/admin/djs")
}
