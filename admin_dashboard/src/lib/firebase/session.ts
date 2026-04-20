import { cookies } from 'next/headers'
import { getFirebaseAdminAuth } from './admin'
import type { DecodedIdToken } from 'firebase-admin/auth'
import { isAdminEmailAllowed } from '@/lib/admin/allowlist'

export const FIREBASE_SESSION_COOKIE = 'firebase_session'

// Raw Firebase session verification (no admin allowlist check).
// Use this for non-admin portals (e.g., DJ dashboard) where access control is
// implemented via app DB lookups instead of ADMIN_EMAILS.
export async function verifyFirebaseSessionCookieRaw(): Promise<DecodedIdToken | null> {
	const cookieStore = await cookies()
	const session = cookieStore.get(FIREBASE_SESSION_COOKIE)?.value
	if (!session) return null

	try {
		const auth = getFirebaseAdminAuth()
		const decoded = await auth.verifySessionCookie(session, true)

		// Enforce immediate blocking via Firebase disabled flag.
		const record = await auth.getUser(decoded.uid)
		if (record.disabled) return null

		return decoded
	} catch {
		return null
	}
}

export async function verifyFirebaseSessionCookie(): Promise<DecodedIdToken | null> {
	const cookieStore = await cookies()
	const session = cookieStore.get(FIREBASE_SESSION_COOKIE)?.value
	if (!session) return null

	try {
		const auth = getFirebaseAdminAuth()
		const decoded = await auth.verifySessionCookie(session, true)

		// Enforce admin allowlist (simple + secure).
		if (!isAdminEmailAllowed(decoded.email ?? null)) return null

		// Enforce immediate blocking via Firebase disabled flag.
		const record = await auth.getUser(decoded.uid)
		if (record.disabled) return null

		return decoded
	} catch {
		return null
	}
}
