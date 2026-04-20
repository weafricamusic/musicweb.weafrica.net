import { NextResponse } from 'next/server'
import { getFirebaseAdminAuth, tryGetFirebaseAdminServiceAccountMeta } from '@/lib/firebase/admin'
import { FIREBASE_SESSION_COOKIE } from '@/lib/firebase/session'
import { assertAdminAllowlistConfigured, isAdminEmailAllowed } from '@/lib/admin/allowlist'
import { SignJWT } from 'jose'

export const runtime = 'nodejs'

const FIVE_DAYS_MS = 5 * 24 * 60 * 60 * 1000
const ADMIN_GUARD_COOKIE = 'admin_guard'

function normalizeSecret(value: string | undefined): string | null {
	if (!value) return null
	const v = value.trim().replace(/^['"]|['"]$/g, '')
	return v.length ? v : null
}

function getGuardSecretOrThrow(): Uint8Array {
	const secret = normalizeSecret(process.env.ADMIN_GUARD_SECRET)
	if (!secret) throw new Error('Missing ADMIN_GUARD_SECRET')
	return new TextEncoder().encode(secret)
}

function getIdTokenFromRequest(req: Request): string | null {
	const header = req.headers.get('authorization')
	if (!header) return null
	const value = header.trim()
	if (!value) return null
	return value.toLowerCase().startsWith('bearer ') ? value.slice('bearer '.length).trim() : null
}

export async function POST(req: Request) {
	let idToken = getIdTokenFromRequest(req)
	if (!idToken) {
		const body = (await req.json().catch(() => ({}))) as { idToken?: string }
		idToken = typeof body.idToken === 'string' ? body.idToken : null
	}
	if (!idToken) {
		return NextResponse.json(
			{ error: 'Missing idToken. Send JSON { idToken } or header Authorization: Bearer <firebase_id_token>.' },
			{ status: 400 },
		)
	}

	try {
		assertAdminAllowlistConfigured()
	} catch (e) {
		return NextResponse.json({ error: e instanceof Error ? e.message : 'Admin access not configured' }, { status: 500 })
	}

	let auth: ReturnType<typeof getFirebaseAdminAuth>
	try {
		auth = getFirebaseAdminAuth()
	} catch (err) {
		console.error('Firebase Admin not configured:', err)
		return NextResponse.json(
			{
				error:
					err instanceof Error
						? err.message
						: 'Firebase Admin is not configured. Set FIREBASE_SERVICE_ACCOUNT_PATH (or GOOGLE_APPLICATION_CREDENTIALS) or FIREBASE_SERVICE_ACCOUNT_JSON/BASE64 in .env.local, then restart the server.',
			},
			{ status: 500 },
		)
	}

	// Verify identity first so we can enforce allowlist.
	let email: string | null = null
	let uid: string | null = null
	try {
		const decoded = await auth.verifyIdToken(idToken)
		email = decoded.email ?? null
		uid = decoded.uid ?? null
		if (!isAdminEmailAllowed(email)) {
			return NextResponse.json({ error: 'Access denied' }, { status: 403 })
		}
	} catch (err) {
		console.error('Failed to verify Firebase idToken:', err)
		return NextResponse.json(
			{
				error:
					'Invalid token. Common cause: Firebase Admin credentials (FIREBASE_SERVICE_ACCOUNT_*) do not match the Firebase project used on the client (NEXT_PUBLIC_FIREBASE_PROJECT_ID). Update Vercel env vars for the same environment (Preview/Production) and redeploy.',
			},
			{ status: 401 },
		)
	}

	let sessionCookie: string
	try {
		sessionCookie = await auth.createSessionCookie(idToken, { expiresIn: FIVE_DAYS_MS })
	} catch (err) {
		const message = err instanceof Error ? err.message : ''
		if (
			typeof message === 'string' &&
			message.toLowerCase().includes('invalid_grant') &&
			message.toLowerCase().includes('invalid jwt signature')
		) {
			const meta = tryGetFirebaseAdminServiceAccountMeta()
			console.error('Failed to create Firebase session cookie: invalid JWT signature', { meta, err })
			return NextResponse.json(
				{
					error:
						'Firebase Admin could not fetch a Google OAuth2 access token (invalid_grant: Invalid JWT Signature).\n\n' +
						'Common causes: (1) the service account key was revoked/deleted, or (2) system time skew.\n\n' +
						(meta?.privateKeyId
							? `Service account key id in use: ${meta.privateKeyId}. If this key id is not present in Firebase Console → Service accounts → Keys, generate a new key and update FIREBASE_SERVICE_ACCOUNT_*.`
							: 'Generate a new service account key in Firebase Console and update FIREBASE_SERVICE_ACCOUNT_* (PATH/JSON/BASE64), then restart/redeploy.'),
				},
				{ status: 500 },
			)
		}
		console.error('Failed to create Firebase session cookie:', err)
		return NextResponse.json(
			{
				error:
					err instanceof Error
						? err.message
						: 'Firebase Admin is not configured. Set FIREBASE_SERVICE_ACCOUNT_PATH (or GOOGLE_APPLICATION_CREDENTIALS) or FIREBASE_SERVICE_ACCOUNT_JSON/BASE64 in .env.local, then restart the server.',
			},
			{ status: 500 },
		)
	}
	const res = NextResponse.json({ ok: true })
	res.cookies.set({
		name: FIREBASE_SESSION_COOKIE,
		value: sessionCookie,
		httpOnly: true,
		secure: process.env.NODE_ENV === 'production',
		sameSite: 'lax',
		path: '/',
		maxAge: Math.floor(FIVE_DAYS_MS / 1000),
	})

	try {
		const secret = getGuardSecretOrThrow()
		const jwt = await new SignJWT({ admin: true, email })
			.setProtectedHeader({ alg: 'HS256' })
			.setSubject(uid ?? '')
			.setIssuedAt()
			.setExpirationTime(Math.floor((Date.now() + FIVE_DAYS_MS) / 1000))
			.sign(secret)

		res.cookies.set({
			name: ADMIN_GUARD_COOKIE,
			value: jwt,
			httpOnly: true,
			secure: process.env.NODE_ENV === 'production',
			sameSite: 'lax',
			path: '/',
			maxAge: Math.floor(FIVE_DAYS_MS / 1000),
		})
	} catch (e) {
		return NextResponse.json(
			{ error: e instanceof Error ? e.message : 'Failed to create admin guard' },
			{ status: 500 },
		)
	}
	return res
}

export async function DELETE() {
	const res = NextResponse.json({ ok: true })
	res.cookies.set({
		name: FIREBASE_SESSION_COOKIE,
		value: '',
		httpOnly: true,
		secure: process.env.NODE_ENV === 'production',
		sameSite: 'lax',
		path: '/',
		maxAge: 0,
	})
	res.cookies.set({
		name: ADMIN_GUARD_COOKIE,
		value: '',
		httpOnly: true,
		secure: process.env.NODE_ENV === 'production',
		sameSite: 'lax',
		path: '/',
		maxAge: 0,
	})
	return res
}
