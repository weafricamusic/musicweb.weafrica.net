import 'server-only'
import { cert, getApps, initializeApp, type ServiceAccount } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getMessaging, type Messaging } from 'firebase-admin/messaging'
import { readFileSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'

type ServiceAccountLike = ServiceAccount & {
	// Common fields in Google service account JSON.
	project_id?: unknown
	client_email?: unknown
	private_key?: unknown
	private_key_id?: unknown
	privateKeyId?: unknown

	[key: string]: unknown
}

function envValue(value: string | undefined): string | null {
	if (!value) return null
	const trimmed = value.trim()
	if (!trimmed) return null
	// Some deployment UIs wrap values in quotes. Strip a single pair.
	return trimmed.replace(/^['"]|['"]$/g, '').trim() || null
}

function normalizeServiceAccount(serviceAccount: unknown): ServiceAccountLike {
	if (!serviceAccount || typeof serviceAccount !== 'object') {
		throw new Error('Firebase service account must be a JSON object')
	}

	const sa = serviceAccount as ServiceAccountLike
	const rawPrivateKey =
		typeof sa.private_key === 'string'
			? sa.private_key
			: typeof sa.privateKey === 'string'
				? sa.privateKey
				: null

	// If the key came from an env var that double-escaped newlines ("\\n"), fix it.
	if (rawPrivateKey && rawPrivateKey.includes('\\n')) {
		const fixed = rawPrivateKey.replace(/\\n/g, '\n')
		if (typeof sa.private_key === 'string') sa.private_key = fixed
		if (typeof sa.privateKey === 'string') sa.privateKey = fixed
	}

	return sa
}

function getServiceAccountMeta(sa: ServiceAccountLike): {
	projectId?: string
	clientEmail?: string
	privateKeyId?: string
} {
	const projectId =
		(typeof sa.project_id === 'string' ? sa.project_id : typeof sa.projectId === 'string' ? sa.projectId : '')
			.toString()
			.trim() || undefined
	const clientEmail =
		(typeof sa.client_email === 'string'
			? sa.client_email
			: typeof sa.clientEmail === 'string'
				? sa.clientEmail
				: '')
			.toString()
			.trim() || undefined
	const privateKeyId =
		(typeof sa.private_key_id === 'string'
			? sa.private_key_id
			: typeof sa.privateKeyId === 'string'
				? sa.privateKeyId
				: '')
			.toString()
			.trim() || undefined
	return { projectId, clientEmail, privateKeyId }
}

function getProjectIdFromEnv(): string | undefined {
	// On the server, these are safe to read via process.env.
	return (
		process.env.FIREBASE_PROJECT_ID?.trim() ||
		process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID?.trim() ||
		process.env.GCLOUD_PROJECT?.trim() ||
		process.env.GOOGLE_CLOUD_PROJECT?.trim()
	)
}

function usingAuthEmulator(): boolean {
	// Firebase Admin SDK respects this env var when set.
	return Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST?.trim())
}

function looksLikeJson(value: string): boolean {
	const trimmed = value.trim()
	return trimmed.startsWith('{') || trimmed.startsWith('[')
}

function looksLikeServiceAccountObject(value: unknown): value is ServiceAccountLike {
	if (!value || typeof value !== 'object') return false
	const v = value as ServiceAccountLike
	const hasClientEmail = typeof v.client_email === 'string' || typeof v.clientEmail === 'string'
	const hasPrivateKey = typeof v.private_key === 'string' || typeof v.privateKey === 'string'
	return hasClientEmail && hasPrivateKey
}

function tryParseJsonServiceAccount(value: string): ServiceAccountLike | null {
	try {
		const parsed = JSON.parse(value)
		if (!looksLikeServiceAccountObject(parsed)) return null
		return normalizeServiceAccount(parsed)
	} catch {
		return null
	}
}

function tryParseBase64JsonServiceAccount(value: string): ServiceAccountLike | null {
	// Heuristic: only attempt if it looks base64-ish and long enough.
	const trimmed = value.trim()
	if (trimmed.length < 64) return null
	if (!/^[A-Za-z0-9+/=_-]+$/.test(trimmed)) return null
	try {
		const decoded = Buffer.from(trimmed, 'base64').toString('utf8').trim()
		if (!looksLikeJson(decoded)) return null
		const parsed = JSON.parse(decoded)
		if (!looksLikeServiceAccountObject(parsed)) return null
		return normalizeServiceAccount(parsed)
	} catch {
		return null
	}
}

function tryReadServiceAccountFromPathOrInline(rawPathOrInline: string): ServiceAccountLike | null {
	const value = rawPathOrInline.trim()
	if (!value) return null

	if (looksLikeJson(value)) {
		const parsed = tryParseJsonServiceAccount(value)
		if (parsed) return parsed
		// If it starts with "{" but can't be parsed, it is almost certainly a broken .env value (e.g. multiline JSON).
		// Don't treat it as a file path (and don't echo it back) to avoid leaking secrets.
		if (process.env.NODE_ENV === 'production') {
			throw new Error(
				'FIREBASE_SERVICE_ACCOUNT_PATH/GOOGLE_APPLICATION_CREDENTIALS looks like JSON but is not valid JSON. If you are pasting the service account, use FIREBASE_SERVICE_ACCOUNT_JSON (single-line) or FIREBASE_SERVICE_ACCOUNT_BASE64 instead.',
			)
		}
		return null
	}

	const parsedB64 = tryParseBase64JsonServiceAccount(value)
	if (parsedB64) return parsedB64

	// Only treat it as a file path if it looks reasonably like one.
	const seemsPathLike =
		value.length <= 512 &&
		!/\s/.test(value) &&
		(value.includes('/') || value.includes('\\') || value.endsWith('.json') || value.startsWith('.'))
	if (!seemsPathLike) return null

	const resolvedPath = isAbsolute(value) ? value : resolve(process.cwd(), value)
	try {
		const raw = readFileSync(resolvedPath, 'utf8')
		return normalizeServiceAccount(JSON.parse(raw))
	} catch (err) {
		const code = (err as { code?: string } | null)?.code
		if (code === 'ENOENT') {
			if (process.env.NODE_ENV === 'production') {
				throw new Error(
					`Firebase service account file not found at ${resolvedPath}. Place the JSON there (or update FIREBASE_SERVICE_ACCOUNT_PATH), then restart the server.`,
				)
			}
			return null
		}
		throw new Error(`Failed to read Firebase service account JSON from ${resolvedPath}`)
	}
}

function readServiceAccount() {
	const rawPathOrInline =
		envValue(process.env.FIREBASE_SERVICE_ACCOUNT_PATH) || envValue(process.env.GOOGLE_APPLICATION_CREDENTIALS)

	// Dev ergonomics: when a credential path is provided, prefer it over JSON/BASE64.
	// This avoids surprises when a stale FIREBASE_SERVICE_ACCOUNT_JSON/BASE64 is still exported in the shell.
	if (process.env.NODE_ENV !== 'production' && rawPathOrInline) {
		const fromPath = tryReadServiceAccountFromPathOrInline(rawPathOrInline)
		if (fromPath) return fromPath
	}

	const json = envValue(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)
	if (json) {
		let parsed: unknown
		try {
			parsed = JSON.parse(json)
		} catch {
			throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON')
		}
		if (!looksLikeServiceAccountObject(parsed)) {
			throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON does not look like a service account (missing client_email/private_key)')
		}
		return normalizeServiceAccount(parsed)
	}

	const b64 = envValue(process.env.FIREBASE_SERVICE_ACCOUNT_BASE64)
	if (b64) {
		let decoded: string
		try {
			decoded = Buffer.from(b64, 'base64').toString('utf8')
		} catch {
			throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 is not valid base64')
		}
		let parsed: unknown
		try {
			parsed = JSON.parse(decoded)
		} catch {
			throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 is not valid base64-encoded JSON')
		}
		if (!looksLikeServiceAccountObject(parsed)) {
			throw new Error(
				'FIREBASE_SERVICE_ACCOUNT_BASE64 does not decode to a service account (missing client_email/private_key)',
			)
		}
		return normalizeServiceAccount(parsed)
	}

	// Support common misconfiguration: some setups accidentally paste JSON (or base64 JSON)
	// into FIREBASE_SERVICE_ACCOUNT_PATH / GOOGLE_APPLICATION_CREDENTIALS.
	if (rawPathOrInline) {
		const fromPath = tryReadServiceAccountFromPathOrInline(rawPathOrInline)
		if (fromPath) return fromPath
	}

	// Local dev fallback: if you have firebase-service-account.json in the repo root,
	// allow it without requiring env var wiring.
	if (process.env.NODE_ENV !== 'production') {
		const defaultPath = resolve(process.cwd(), 'firebase-service-account.json')
		try {
			const raw = readFileSync(defaultPath, 'utf8')
			return normalizeServiceAccount(JSON.parse(raw))
		} catch (err) {
			const code = (err as { code?: string } | null)?.code
			if (code !== 'ENOENT') {
				throw new Error(`Failed to read Firebase service account JSON from ${defaultPath}`)
			}
		}
	}

	throw new Error(
		'Missing Firebase admin credentials. Set FIREBASE_SERVICE_ACCOUNT_PATH (or GOOGLE_APPLICATION_CREDENTIALS), or FIREBASE_SERVICE_ACCOUNT_JSON, or FIREBASE_SERVICE_ACCOUNT_BASE64 in .env.local.\n\n' +
			'Local dev quickstart: create admin_dashboard/firebase-service-account.json (copy firebase-service-account.json.example) or run: npm --prefix admin_dashboard run setup:firebase-admin -- --from-clipboard (macOS) / --from <path-to-json>.',
	)
}

let cachedAuth: ReturnType<typeof getAuth> | null = null
let cachedMessaging: Messaging | null = null

export function tryGetFirebaseAdminServiceAccountMeta(): ReturnType<typeof getServiceAccountMeta> | null {
	try {
		const sa = readServiceAccount()
		return getServiceAccountMeta(sa)
	} catch {
		return null
	}
}

export function getFirebaseAdminAuth() {
	if (cachedAuth) return cachedAuth
	const app = getApps().length
		? getApps()[0]!
		: (() => {
			// Local dev ergonomics: allow Auth Emulator usage without a service account.
			// In production, a service account is still required.
			if (usingAuthEmulator()) {
				const projectId = getProjectIdFromEnv()
				if (!projectId) {
					throw new Error(
						'Missing Firebase project id while using the Auth Emulator. Set FIREBASE_PROJECT_ID (recommended) or NEXT_PUBLIC_FIREBASE_PROJECT_ID, then restart the server.',
					)
				}
				return initializeApp({ projectId })
			}
			return initializeApp({
				credential: cert(readServiceAccount()),
			})
		})()
	cachedAuth = getAuth(app)
	return cachedAuth
}

export function getFirebaseAdminMessaging() {
	if (cachedMessaging) return cachedMessaging
	const app = getApps().length
		? getApps()[0]!
		: initializeApp({
				credential: cert(readServiceAccount()),
			})
	cachedMessaging = getMessaging(app)
	return cachedMessaging
}
