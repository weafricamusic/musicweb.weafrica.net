'use server'

import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { getSupabaseAdmin } from '@/lib/supabase-admin'

export type VerificationBucket = 'pending' | 'approved' | 'rejected'

export type ArtistVerificationRow = {
	id: string
	stage_name: string | null
	approved: boolean
	status: 'pending' | 'active' | 'blocked'
	blocked: boolean
	verified: boolean
	created_at: string
}

export type DjVerificationRow = {
	id: string
	dj_name: string | null
	approved: boolean
	status: 'pending' | 'active' | 'blocked'
	blocked: boolean
	created_at: string
}

function normalizeCreatorStatus(input: { approved?: boolean | null; status?: string | null; blocked?: boolean | null }):
	| 'pending'
	| 'active'
	| 'blocked' {
	if (input.blocked === true) return 'blocked'
	if (input.status === 'blocked') return 'blocked'
	if (input.status === 'active') return 'active'
	if (input.approved === true) return 'active'
	return 'pending'
}

function bucketMatches(bucket: VerificationBucket, normalized: 'pending' | 'active' | 'blocked'): boolean {
	if (bucket === 'pending') return normalized === 'pending'
	if (bucket === 'approved') return normalized === 'active'
	return normalized === 'blocked'
}

export async function getArtistVerificationRows(bucket: VerificationBucket): Promise<ArtistVerificationRow[]> {
	const adminCtx = await getAdminContext()
	if (!adminCtx) throw new Error('Unauthorized')
	try {
		assertPermission(adminCtx, 'can_manage_artists')
	} catch {
		throw new Error('Forbidden')
	}

	const supabase = getSupabaseAdmin()

	let data: any[] | null = null
	let error: any = null
	;({ data, error } = await supabase
		.from('artists')
		.select('id,stage_name,approved,status,blocked,verified,created_at')
		.order('created_at', { ascending: false })
		.limit(200))
	if (error) {
		// Older schema fallback
		;({ data, error } = await supabase
			.from('artists')
			.select('id,stage_name,approved,created_at')
			.order('created_at', { ascending: false })
			.limit(200))
	}
	if (error) throw error

	const rows = (data ?? []) as Array<{
		id: string
		stage_name?: string | null
		approved?: boolean | null
		status?: string | null
		blocked?: boolean | null
		verified?: boolean | null
		created_at: string
	}>

	return rows
		.map((a) => {
			const normalized = normalizeCreatorStatus(a)
			return {
				id: a.id,
				stage_name: a.stage_name ?? null,
				approved: a.approved === true,
				status: normalized,
				blocked: a.blocked === true || normalized === 'blocked',
				verified: a.verified === true,
				created_at: a.created_at,
			}
		})
		.filter((r) => bucketMatches(bucket, r.status))
}

export async function getDjVerificationRows(bucket: VerificationBucket): Promise<DjVerificationRow[]> {
	const adminCtx = await getAdminContext()
	if (!adminCtx) throw new Error('Unauthorized')
	try {
		assertPermission(adminCtx, 'can_manage_djs')
	} catch {
		throw new Error('Forbidden')
	}

	const supabase = getSupabaseAdmin()

	let data: any[] | null = null
	let error: any = null
	;({ data, error } = await supabase
		.from('djs')
		.select('id,dj_name,approved,status,blocked,created_at')
		.order('created_at', { ascending: false })
		.limit(200))
	if (error) {
		;({ data, error } = await supabase
			.from('djs')
			.select('id,dj_name,approved,created_at')
			.order('created_at', { ascending: false })
			.limit(200))
	}
	if (error) throw error

	const rows = (data ?? []) as Array<{
		id: string
		dj_name?: string | null
		approved?: boolean | null
		status?: string | null
		blocked?: boolean | null
		created_at: string
	}>

	return rows
		.map((d) => {
			const normalized = normalizeCreatorStatus(d)
			return {
				id: d.id,
				dj_name: d.dj_name ?? null,
				approved: d.approved === true,
				status: normalized,
				blocked: d.blocked === true || normalized === 'blocked',
				created_at: d.created_at,
			}
		})
		.filter((r) => bucketMatches(bucket, r.status))
}
