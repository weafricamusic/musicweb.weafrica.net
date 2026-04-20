import dotenv from 'dotenv'
import { readFileSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'
import { execFileSync } from 'node:child_process'
import { initializeApp, getApps, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'

// Use override so values pulled via `vercel env pull` reliably apply.
dotenv.config({ path: '.env.local', override: true })

function getEnv(name) {
	const v = (process.env[name] || '').trim()
	return v || null
}

function shouldUseVercelCurl(baseUrl) {
	try {
		const u = new URL(baseUrl)
		return u.hostname.endsWith('vercel.app') && String(process.env.SMOKE_USE_VERCEL_CURL || '1').trim() !== '0'
	} catch {
		return false
	}
}

function vercelCurlRequestWithHeaders({ deploymentUrl, path, method, headers, body, cookie }) {
	const headerArgs = []
	for (const [k, v] of Object.entries(headers || {})) {
		if (v == null) continue
		headerArgs.push('--header', `${k}: ${String(v)}`)
	}
	const bodyArgs = body != null ? ['--data-raw', String(body)] : []
	const cookieArgs = cookie ? ['--cookie', String(cookie)] : []
	const writeOut = '\n__HTTP_CODE__:%{http_code}\n'

	const out = execFileSync(
		'vercel',
		[
			'curl',
			path,
			'--deployment',
			deploymentUrl,
			'--',
			'--silent',
			'--show-error',
			'--location',
			'--include',
			'--write-out',
			writeOut,
			'--request',
			method,
			...cookieArgs,
			...headerArgs,
			...bodyArgs,
		],
		{ encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
	)

	const lines = out.split('\n')
	const markerIdx = lines.findIndex((l) => l.startsWith('__HTTP_CODE__:'))
	const status = markerIdx >= 0 ? Number(lines[markerIdx].slice('__HTTP_CODE__:'.length)) : 0
	const payload = markerIdx >= 0 ? lines.slice(0, markerIdx).join('\n') : out

	const setCookies = []
	for (const m of payload.matchAll(/^set-cookie:\s*([^\r\n]+)$/gim)) {
		setCookies.push(m[1].trim())
	}

	// With --include, headers + body are printed. Grab the last block after the final blank line.
	const parts = payload.split(/\r?\n\r?\n/)
	const text = parts.length ? parts[parts.length - 1] : payload

	return { status, text, setCookies }
}

function parseCookieValue(setCookieLine, name) {
	const prefix = `${name}=`
	const idx = setCookieLine.toLowerCase().indexOf(prefix.toLowerCase())
	if (idx < 0) return null
	const rest = setCookieLine.slice(idx + prefix.length)
	const end = rest.indexOf(';')
	return (end >= 0 ? rest.slice(0, end) : rest).trim() || null
}

function sanitizeJsonWithRawNewlinesInsideStrings(input) {
	let out = ''
	let inString = false
	let escaped = false
	for (let i = 0; i < input.length; i++) {
		const ch = input[i]
		if (escaped) {
			out += ch
			escaped = false
			continue
		}
		if (ch === '\\') {
			out += ch
			escaped = true
			continue
		}
		if (ch === '"') {
			inString = !inString
			out += ch
			continue
		}
		if (inString && ch === '\n') {
			out += '\\n'
			continue
		}
		if (inString && ch === '\r') {
			out += '\\r'
			continue
		}
		out += ch
	}
	return out
}

function readServiceAccount() {
	const rawPath = (process.env.FIREBASE_SERVICE_ACCOUNT_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS || '').trim()
	if (rawPath) {
		const resolvedPath = isAbsolute(rawPath) ? rawPath : resolve(process.cwd(), rawPath)
		const raw = readFileSync(resolvedPath, 'utf8')
		return JSON.parse(raw)
	}

	const b64 = (process.env.FIREBASE_SERVICE_ACCOUNT_BASE64 || '').trim()
	if (b64) {
		try {
			return JSON.parse(Buffer.from(b64, 'base64').toString('utf8'))
		} catch {
			// fall through
		}
	}

	const json = (process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '').trim()
	if (json) {
		try {
			return JSON.parse(json)
		} catch {
			try {
				return JSON.parse(sanitizeJsonWithRawNewlinesInsideStrings(json))
			} catch {
				throw new Error(
					'FIREBASE_SERVICE_ACCOUNT_JSON is set but not valid JSON. Prefer FIREBASE_SERVICE_ACCOUNT_BASE64 instead.',
				)
			}
		}
	}

	throw new Error(
		'Missing Firebase admin credentials. Set FIREBASE_SERVICE_ACCOUNT_PATH (or GOOGLE_APPLICATION_CREDENTIALS), or FIREBASE_SERVICE_ACCOUNT_JSON/BASE64 in .env.local.',
	)
}

function getFirebaseAdminAuth() {
	if (getApps().length === 0) {
		initializeApp({ credential: cert(readServiceAccount()) })
	}
	return getAuth()
}

async function exchangeCustomTokenForIdToken({ apiKey, customToken }) {
	const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`
	const res = await fetch(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ token: customToken, returnSecureToken: true }),
	})
	const data = await res.json().catch(() => null)
	if (!res.ok) {
		throw new Error(`Failed to exchange custom token: ${res.status} ${JSON.stringify(data)}`)
	}
	const idToken = data?.idToken
	if (!idToken) throw new Error('Missing idToken in exchange response')
	return idToken
}

async function main() {
	const baseUrl = (
		process.argv[2] ||
		process.env.SMOKE_BASE_URL ||
		process.env.WEAFRICA_API_BASE_URL ||
		process.env.NEXT_PUBLIC_WEAFRICA_API_BASE_URL ||
		'http://127.0.0.1:3010'
	).trim()

	const apiKey = getEnv('NEXT_PUBLIC_FIREBASE_API_KEY')
	if (!apiKey) throw new Error('Missing NEXT_PUBLIC_FIREBASE_API_KEY')

	const adminEmail = (process.env.TEST_ADMIN_EMAIL || 'admin@weafrica.test').trim().toLowerCase()

	console.log(`Base URL: ${baseUrl}`)
	console.log(`Admin email: ${adminEmail}`)

	// 1) Mint an ID token for the admin user (no browser required)
	const auth = getFirebaseAdminAuth()
	let user
	try {
		user = await auth.getUserByEmail(adminEmail)
	} catch (e) {
		const msg = String(e?.message ?? e)
		if (/user[- ]not[- ]found/i.test(msg) || /auth\/user-not-found/i.test(msg)) {
			user = await auth.createUser({ email: adminEmail })
		} else {
			throw e
		}
	}

	const customToken = await auth.createCustomToken(user.uid)
	const idToken = await exchangeCustomTokenForIdToken({ apiKey, customToken })
	console.log('Firebase ID token OK')

	const base = baseUrl.replace(/\/$/, '')

	// 2) Create server session cookies via /api/auth/session
	const sessionPayload = JSON.stringify({ idToken })
	let firebaseSession = null
	let adminGuard = null
	if (shouldUseVercelCurl(base)) {
		const { status, text, setCookies } = vercelCurlRequestWithHeaders({
			deploymentUrl: base,
			path: '/api/auth/session',
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: sessionPayload,
		})
		for (const sc of setCookies) {
			firebaseSession = firebaseSession || parseCookieValue(sc, 'firebase_session')
			adminGuard = adminGuard || parseCookieValue(sc, 'admin_guard')
		}
		if (status !== 200) {
			throw new Error(`Failed to create session cookie: ${status} ${text}`)
		}
		if (!firebaseSession) {
			throw new Error('No firebase_session cookie returned by /api/auth/session')
		}
	} else {
		const res = await fetch(`${base}/api/auth/session`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: sessionPayload,
		})
		const text = await res.text()
		const setCookie = (res.headers.getSetCookie?.() ?? (res.headers.get('set-cookie') ? [res.headers.get('set-cookie')] : [])).filter(Boolean)
		for (const sc of setCookie) {
			firebaseSession = firebaseSession || parseCookieValue(sc, 'firebase_session')
			adminGuard = adminGuard || parseCookieValue(sc, 'admin_guard')
		}
		if (!res.ok) throw new Error(`Failed to create session cookie: ${res.status} ${text}`)
		if (!firebaseSession) throw new Error('No firebase_session cookie returned by /api/auth/session')
	}

	const cookieHeader = [`firebase_session=${firebaseSession}`, adminGuard ? `admin_guard=${adminGuard}` : null]
		.filter(Boolean)
		.join('; ')
	console.log('Session cookie OK')

	// 3) Bootstrap the admin row in Supabase (or legacy table)
	let bootstrap
	if (shouldUseVercelCurl(base)) {
		bootstrap = vercelCurlRequestWithHeaders({
			deploymentUrl: base,
			path: '/api/admin/bootstrap',
			method: 'POST',
			headers: {},
			cookie: cookieHeader,
		})
	} else {
		const res = await fetch(`${base}/api/admin/bootstrap`, { method: 'POST', headers: { cookie: cookieHeader } })
		bootstrap = { status: res.status, text: await res.text(), setCookies: [] }
	}
	if (bootstrap.status !== 200) {
		throw new Error(`Bootstrap failed: ${bootstrap.status} ${bootstrap.text}`)
	}
	console.log(`Bootstrap OK: ${bootstrap.text.trim()}`)

	// 4) Hit an admin-protected API route that requires Supabase service-role
	let artists
	const path = '/api/admin/verification/artists?bucket=pending'
	if (shouldUseVercelCurl(base)) {
		artists = vercelCurlRequestWithHeaders({
			deploymentUrl: base,
			path,
			method: 'GET',
			headers: {},
			cookie: cookieHeader,
		})
	} else {
		const res = await fetch(`${base}${path}`, { headers: { cookie: cookieHeader } })
		artists = { status: res.status, text: await res.text(), setCookies: [] }
	}

	if (artists.status === 200) {
		console.log('✅ Admin API access OK (verification/artists)')
		return
	}
	console.log(`❌ Admin API check failed: ${artists.status}`)
	console.log(artists.text)
	process.exit(1)
}

main().catch((err) => {
	console.error('Smoke admin dashboard failed:', err?.message ?? err)
	process.exit(1)
})
