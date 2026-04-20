import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'

function normalizeId(value: unknown): string | null {
	const s = typeof value === 'string' ? value.trim() : ''
	return s ? s : null
}

export function isUuidLike(value: string): boolean {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
}

export type FirebaseUidResolution = {
	input: string
	firebaseUid: string | null
	via:
		| 'users.firebase_uid'
		| 'users.uid'
		| 'users.id'
		| 'artists.firebase_uid'
		| 'artists.id'
		| 'artists.user_id'
		| 'djs.firebase_uid'
		| 'djs.id'
		| 'djs.user_id'
		| null
}

/**
 * Best-effort resolver that takes *any* identifier (Firebase UID, legacy uuid id, etc)
 * and returns the Firebase UID when it can be derived from Supabase tables.
 */
export async function tryResolveFirebaseUidFromAnyUserId(args: {
	supabase: SupabaseClient
	userId: string
}): Promise<FirebaseUidResolution> {
	const input = normalizeId(args.userId) ?? ''
	if (!input) return { input: '', firebaseUid: null, via: null }

	// 1) Already a Firebase UID in `users`.
	try {
		const { data, error } = await args.supabase
			.from('users')
			.select('firebase_uid')
			.eq('firebase_uid', input)
			.maybeSingle<any>()
		if (!error) {
			const uid = normalizeId(data?.firebase_uid)
			if (uid) return { input, firebaseUid: uid, via: 'users.firebase_uid' }
		}
	} catch {
		// ignore
	}

	// 1b) Some schemas store Firebase UID in `users.uid`.
	try {
		const { data, error } = await args.supabase
			.from('users')
			.select('firebase_uid,uid')
			.eq('uid', input)
			.maybeSingle<any>()
		if (!error && data) {
			const uid = normalizeId(data?.firebase_uid) ?? normalizeId(data?.uid)
			if (uid) return { input, firebaseUid: uid, via: 'users.uid' }
		}
	} catch {
		// ignore
	}

	// 2) Already a Firebase UID in creators.
	for (const table of ['artists', 'djs'] as const) {
		try {
			const { data, error } = await args.supabase
				.from(table)
				.select('firebase_uid')
				.eq('firebase_uid', input)
				.maybeSingle<any>()
			if (!error) {
				const uid = normalizeId(data?.firebase_uid)
				if (uid) return { input, firebaseUid: uid, via: `${table}.firebase_uid` }
			}
		} catch {
			// ignore
		}
	}

	// 3) UUID -> Firebase UID mapping.
	if (isUuidLike(input)) {
		try {
			const { data, error } = await args.supabase
				.from('users')
				.select('firebase_uid')
				.eq('id', input)
				.maybeSingle<any>()
			if (!error) {
				const uid = normalizeId(data?.firebase_uid)
				if (uid) return { input, firebaseUid: uid, via: 'users.id' }
			}
		} catch {
			// ignore
		}

		for (const table of ['artists', 'djs'] as const) {
			try {
				const { data, error } = await args.supabase
					.from(table)
					.select('firebase_uid')
					.eq('id', input)
					.maybeSingle<any>()
				if (!error) {
					const uid = normalizeId(data?.firebase_uid)
					if (uid) return { input, firebaseUid: uid, via: `${table}.id` }
				}
			} catch {
				// ignore
			}
		}
	}

	// 4) Legacy: creator rows linked by `user_id`.
	for (const table of ['artists', 'djs'] as const) {
		try {
			const { data, error } = await args.supabase
				.from(table)
				.select('firebase_uid,user_id')
				.eq('user_id', input)
				.maybeSingle<any>()
			if (!error && data) {
				const uid = normalizeId(data?.firebase_uid)
				if (uid) return { input, firebaseUid: uid, via: `${table}.user_id` }
			}
		} catch {
			// ignore
		}
	}

	return { input, firebaseUid: null, via: null }
}

export type CanonicalSubscriptionUserId = {
	inputUserId: string
	canonicalUserId: string
	resolvedFirebaseUid: string | null
	resolvedVia: FirebaseUidResolution['via']
}

/**
 * Returns the canonical subscription key we should store in `user_subscriptions.user_id`.
 * Prefer Firebase UID when resolvable; otherwise keep the trimmed input as-is.
 */
export async function resolveCanonicalSubscriptionUserId(args: {
	supabase: SupabaseClient
	userId: string
}): Promise<CanonicalSubscriptionUserId> {
	const inputUserId = normalizeId(args.userId) ?? ''
	if (!inputUserId) {
		return { inputUserId: '', canonicalUserId: '', resolvedFirebaseUid: null, resolvedVia: null }
	}

	const resolved = await tryResolveFirebaseUidFromAnyUserId({ supabase: args.supabase, userId: inputUserId })
	const canonicalUserId = resolved.firebaseUid ?? inputUserId
	return {
		inputUserId,
		canonicalUserId,
		resolvedFirebaseUid: resolved.firebaseUid,
		resolvedVia: resolved.via,
	}
}

/**
 * When the app authenticates via Firebase UID, older subscription rows may still be keyed
 * by internal UUID ids. This returns a set of IDs that belong to the same Firebase user.
 */
export async function getSubscriptionUserIdCandidatesForFirebaseUid(args: {
	supabase: SupabaseClient
	firebaseUid: string
}): Promise<string[]> {
	const uid = normalizeId(args.firebaseUid)
	if (!uid) return []

	const out = new Set<string>([uid])

	// `users` table (consumer profiles)
	try {
		const { data, error } = await args.supabase
			.from('users')
			.select('id,firebase_uid,uid')
			.or(`firebase_uid.eq.${uid},uid.eq.${uid}`)
			.limit(1)
			.maybeSingle<any>()
		if (!error && data) {
			const id = normalizeId(data?.id)
			const firebaseUid = normalizeId(data?.firebase_uid)
			const legacyUid = normalizeId(data?.uid)
			if (id) out.add(id)
			if (firebaseUid) out.add(firebaseUid)
			if (legacyUid) out.add(legacyUid)
		}
	} catch {
		// ignore
	}

	// creators tables
	for (const table of ['artists', 'djs'] as const) {
		try {
			let data: any | null = null
			let error: any = null
			;({ data, error } = await args.supabase
				.from(table)
				.select('id,firebase_uid,user_id')
				.eq('firebase_uid', uid)
				.limit(1)
				.maybeSingle<any>())

			if (error && String(error.message ?? '').includes(`column ${table}.user_id does not exist`)) {
				;({ data, error } = await args.supabase
					.from(table)
					.select('id,firebase_uid')
					.eq('firebase_uid', uid)
					.limit(1)
					.maybeSingle<any>())
			}

			if (!error && data) {
				const id = normalizeId(data?.id)
				const firebaseUid = normalizeId(data?.firebase_uid)
				const userId = normalizeId(data?.user_id)
				if (id) out.add(id)
				if (firebaseUid) out.add(firebaseUid)
				if (userId) out.add(userId)
			}
		} catch {
			// ignore
		}
	}

	return Array.from(out).filter(Boolean)
}
