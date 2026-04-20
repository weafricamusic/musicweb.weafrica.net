import 'server-only'

import { getFirebaseAdminAuth } from '@/lib/firebase/admin'

export type SubscriptionClaims = {
	plan_id: string
	status: 'active' | 'canceled' | 'expired' | 'replaced' | 'none'
	ends_at?: string | null
}

/**
 * Best-effort sync of subscription state into Firebase custom claims.
 *
 * Why:
 * - Lets the consumer app read plan/status from the Firebase ID token quickly.
 * - Still keep `/api/subscriptions/me` as source-of-truth (tokens can be stale until refresh).
 */
export async function trySetSubscriptionClaims(uid: string, claims: SubscriptionClaims): Promise<void> {
	const safeUid = String(uid ?? '').trim()
	if (!safeUid) return

	// Keep payload small (< 1KB).
	const payload: Record<string, unknown> = {
		sub_plan: String(claims.plan_id ?? 'free'),
		sub_status: String(claims.status ?? 'none'),
	}
	if (claims.ends_at) payload.sub_ends_at = String(claims.ends_at)

	try {
		const auth = getFirebaseAdminAuth()
		const user = await auth.getUser(safeUid)
		const current = (user.customClaims ?? {}) as Record<string, unknown>
		const next: Record<string, unknown> = { ...current, ...payload }
		// If ends_at is missing, clear any previous value.
		if (!claims.ends_at && 'sub_ends_at' in next) delete next.sub_ends_at
		await auth.setCustomUserClaims(safeUid, next)
	} catch {
		// best-effort: never fail the webhook/admin operation because of claims
	}
}
