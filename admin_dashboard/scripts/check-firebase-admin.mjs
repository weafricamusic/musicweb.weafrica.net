import { readFileSync, existsSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'
import dotenv from 'dotenv'
import { cert } from 'firebase-admin/app'

// Mirror Next.js local dev behavior: read .env.local if present.
dotenv.config({ path: '.env.local' })

function envValue(value) {
	if (!value) return null
	const trimmed = String(value).trim()
	if (!trimmed) return null
	// Some UIs wrap values in quotes. Strip one pair.
	return trimmed.replace(/^['"]|['"]$/g, '').trim() || null
}

function looksLikeJson(value) {
	const t = String(value || '').trim()
	return t.startsWith('{') || t.startsWith('[')
}

function normalizeServiceAccount(sa) {
	if (!sa || typeof sa !== 'object') throw new Error('Firebase service account must be a JSON object')
	// Fix common env-var escaping: "\\n" instead of real newlines.
	if (typeof sa.private_key === 'string' && sa.private_key.includes('\\n')) {
		sa.private_key = sa.private_key.replace(/\\n/g, '\n')
	}
	if (typeof sa.privateKey === 'string' && sa.privateKey.includes('\\n')) {
		sa.privateKey = sa.privateKey.replace(/\\n/g, '\n')
	}
	return sa
}

function looksLikeServiceAccountObject(value) {
	if (!value || typeof value !== 'object') return false
	return (
		(typeof value.client_email === 'string' || typeof value.clientEmail === 'string') &&
		(typeof value.private_key === 'string' || typeof value.privateKey === 'string')
	)
}

function tryParseJsonServiceAccount(value) {
	try {
		const parsed = JSON.parse(String(value))
		if (!looksLikeServiceAccountObject(parsed)) return null
		return normalizeServiceAccount(parsed)
	} catch {
		return null
	}
}

function tryParseBase64JsonServiceAccount(value) {
	const trimmed = String(value || '').trim()
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

function readServiceAccountFromEnvOrFile() {
	// Dev ergonomics: if a credential file path is provided, prefer it over JSON/BASE64.
	// This avoids surprises when stale FIREBASE_SERVICE_ACCOUNT_JSON/BASE64 is still exported in the shell.
	if (process.env.NODE_ENV !== 'production') {
		const rawPathOrInline = envValue(process.env.FIREBASE_SERVICE_ACCOUNT_PATH) || envValue(process.env.GOOGLE_APPLICATION_CREDENTIALS)
		if (rawPathOrInline) {
			// Detect common mistakes: JSON/base64 pasted into *_PATH.
			if (looksLikeJson(rawPathOrInline)) {
				const parsed = tryParseJsonServiceAccount(rawPathOrInline)
				if (parsed) return parsed
			} else {
				const parsedB64 = tryParseBase64JsonServiceAccount(rawPathOrInline)
				if (parsedB64) return parsedB64
			}

			const resolvedPath = resolvePath(rawPathOrInline)
			if (resolvedPath && existsSync(resolvedPath)) {
				const raw = readFileSync(resolvedPath, 'utf8')
				const parsed = JSON.parse(raw)
				if (!looksLikeServiceAccountObject(parsed)) {
					throw new Error('Service account JSON file is missing client_email/private_key')
				}
				return normalizeServiceAccount(parsed)
			}
		}
	}

	const json = envValue(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)
	if (json) {
		const parsed = tryParseJsonServiceAccount(json)
		if (!parsed) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is set but not valid service account JSON')
		return parsed
	}

	const b64 = envValue(process.env.FIREBASE_SERVICE_ACCOUNT_BASE64)
	if (b64) {
		const parsed = tryParseBase64JsonServiceAccount(b64)
		if (!parsed) throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 is set but not valid base64-encoded service account JSON')
		return parsed
	}

	const rawPathOrInline = envValue(process.env.FIREBASE_SERVICE_ACCOUNT_PATH) || envValue(process.env.GOOGLE_APPLICATION_CREDENTIALS)
	if (!rawPathOrInline) return null

	// Detect common mistakes: JSON/base64 pasted into *_PATH.
	if (looksLikeJson(rawPathOrInline)) {
		const parsed = tryParseJsonServiceAccount(rawPathOrInline)
		if (parsed) return parsed
		throw new Error(
			'FIREBASE_SERVICE_ACCOUNT_PATH/GOOGLE_APPLICATION_CREDENTIALS looks like JSON but is not valid. Use FIREBASE_SERVICE_ACCOUNT_JSON (single-line) or FIREBASE_SERVICE_ACCOUNT_BASE64 instead.',
		)
	}
	const parsedB64 = tryParseBase64JsonServiceAccount(rawPathOrInline)
	if (parsedB64) return parsedB64

	// Treat as file path.
	const resolvedPath = resolvePath(rawPathOrInline)
	if (!resolvedPath) return null
	if (!existsSync(resolvedPath)) {
		throw new Error(
			`Firebase service account file not found at ${resolvedPath}. ` +
				'Create the file (recommended for local dev) or set FIREBASE_SERVICE_ACCOUNT_JSON/BASE64.',
		)
	}
	const raw = readFileSync(resolvedPath, 'utf8')
	const parsed = JSON.parse(raw)
	if (!looksLikeServiceAccountObject(parsed)) {
		throw new Error('Service account JSON file is missing client_email/private_key')
	}
	return normalizeServiceAccount(parsed)
}

function resolvePath(rawPath) {
	if (!rawPath) return null
	const trimmed = String(rawPath).trim()
	if (!trimmed) return null
	return isAbsolute(trimmed) ? trimmed : resolve(process.cwd(), trimmed)
}

const rawPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS
const resolvedPath = resolvePath(rawPath)

try {
	const sa = readServiceAccountFromEnvOrFile()
	if (!sa) {
		console.error(
			'No Firebase Admin credentials found.\n' +
				'Set one of: FIREBASE_SERVICE_ACCOUNT_JSON, FIREBASE_SERVICE_ACCOUNT_BASE64, FIREBASE_SERVICE_ACCOUNT_PATH, or GOOGLE_APPLICATION_CREDENTIALS.',
		)
		process.exit(1)
	}

	const projectId = sa.project_id || sa.projectId
	const clientEmail = sa.client_email || sa.clientEmail
	const privateKeyId = sa.private_key_id || sa.privateKeyId
	const missing = ['project_id', 'client_email', 'private_key'].filter((k) => !sa?.[k])
	if (missing.length) {
		console.error(`Service account JSON is missing: ${missing.join(', ')}`)
		process.exit(1)
	}

	console.log('Firebase Admin service account looks OK:')
	if (projectId) console.log(`- project_id: ${projectId}`)
	if (clientEmail) console.log(`- client_email: ${clientEmail}`)
	if (privateKeyId) console.log(`- private_key_id: ${privateKeyId}`)
	if (!resolvedPath) console.log('- source: env (JSON/BASE64)')
	else console.log(`- source: file (${resolvedPath})`)

	if (process.argv.includes('--token')) {
		try {
			const credential = cert(sa)
			const token = await credential.getAccessToken()
			console.log('OAuth2 access token fetch: OK')
			if (token?.expires_in) console.log(`- expires_in: ${token.expires_in}s`)
		} catch (e) {
			console.error('OAuth2 access token fetch: FAILED')
			console.error(
				'This usually means your service account key was revoked/deleted, or your system clock is skewed.\n' +
					'Re-generate a new key: Firebase Console → Project settings → Service accounts → Generate new private key.',
			)
			console.error(e?.message || e)
			process.exit(1)
		}
	}

	process.exit(0)
} catch (e) {
	console.error(e?.message || e)
	process.exit(1)
}
