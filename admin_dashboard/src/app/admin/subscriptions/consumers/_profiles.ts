import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

import { isUuidLike } from '@/lib/subscription/resolve-user-id'

export type UserProfileRow = {
	id?: string | null
	firebase_uid?: string | null
	uid?: string | null
	username?: string | null
	email?: string | null
}

function normalizeId(value: unknown): string | null {
	const s = typeof value === 'string' ? value.trim() : ''
	return s ? s : null
}

function isMissingColumn(message: unknown, column: string): boolean {
	const s = String(message ?? '')
	return s.includes(`column users.${column} does not exist`)
}

async function queryUsersByColumn(args: {
	supabase: SupabaseClient
	column: 'firebase_uid' | 'uid' | 'id'
	values: string[]
}): Promise<UserProfileRow[]> {
	if (!args.values.length) return []

	const attempts = [
		'id,firebase_uid,uid,username,email',
		'id,firebase_uid,username,email',
		'firebase_uid,username,email',
	]

	for (const select of attempts) {
		const { data, error } = await args.supabase.from('users').select(select).in(args.column, args.values).limit(500)
		if (!error) return (data ?? []) as any
		if (isMissingColumn(error.message, 'uid') && select.includes('uid')) continue
		if (isMissingColumn(error.message, 'id') && select.includes('id')) continue
		if (isMissingColumn(error.message, args.column)) return []
		return []
	}

	return []
}

/**
 * Best-effort lookup for consumer profiles keyed by different identifier styles.
 *
 * Why: older systems sometimes store subscription.user_id as a UUID while newer systems
 * store Firebase UID. This returns a map keyed by all known identifiers for quick joins.
 */
export async function loadUserProfilesByAnyId(args: {
	supabase: SupabaseClient
	userIds: string[]
}): Promise<Map<string, UserProfileRow>> {
	const normalized = Array.from(new Set(args.userIds.map(normalizeId).filter((v): v is string => Boolean(v))))
	const out = new Map<string, UserProfileRow>()
	if (!normalized.length) return out

	const uuidIds = normalized.filter((v) => isUuidLike(v))
	const nonUuidIds = normalized.filter((v) => !isUuidLike(v))

	let rows: UserProfileRow[] = []
	try {
		rows = rows.concat(await queryUsersByColumn({ supabase: args.supabase, column: 'firebase_uid', values: nonUuidIds }))
	} catch {
		// ignore
	}

	try {
		rows = rows.concat(await queryUsersByColumn({ supabase: args.supabase, column: 'uid', values: nonUuidIds }))
	} catch {
		// ignore
	}

	try {
		rows = rows.concat(await queryUsersByColumn({ supabase: args.supabase, column: 'id', values: uuidIds }))
	} catch {
		// ignore
	}

	for (const r of rows) {
		const firebaseUid = normalizeId((r as any)?.firebase_uid)
		const uid = normalizeId((r as any)?.uid)
		const id = normalizeId((r as any)?.id)
		if (firebaseUid) out.set(firebaseUid, r)
		if (uid) out.set(uid, r)
		if (id) out.set(id, r)
	}

	return out
}
