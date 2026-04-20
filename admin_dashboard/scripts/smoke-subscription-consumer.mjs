import dotenv from 'dotenv'
import { readFileSync } from 'node:fs'
import { isAbsolute, resolve } from 'node:path'
import { createHmac } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { initializeApp, getApps, cert } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'

// Mirror Next.js local dev behavior.
// Use override so values pulled via `vercel env pull` reliably apply even if the parent
// process already has empty env vars set.
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

function vercelCurlRequest({ deploymentUrl, path, method, headers, body }) {
	const headerArgs = []
	for (const [k, v] of Object.entries(headers || {})) {
		if (v == null) continue
		headerArgs.push('--header', `${k}: ${String(v)}`)
	}
	const bodyArgs = body ? ['--data-raw', body] : []
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
			'--write-out',
			writeOut,
			'--request',
			method,
			...headerArgs,
			...bodyArgs,
		],
		{ encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
	)

	const lines = out.split('\n')
	const markerIdx = lines.findIndex((l) => l.startsWith('__HTTP_CODE__:'))
	const status = markerIdx >= 0 ? Number(lines[markerIdx].slice('__HTTP_CODE__:'.length)) : 0
	const text = markerIdx >= 0 ? lines.slice(0, markerIdx).join('\n') : out
	return { status, text }
}

async function postPayChanguStart({ baseUrl, uid, planId, months, countryCode }) {
	const base = baseUrl.replace(/\/$/, '')
	const payload = {
		user_id: uid,
		plan_id: planId,
		months,
		country_code: countryCode,
	}
	const rawBody = JSON.stringify(payload)

	if (shouldUseVercelCurl(base)) {
		const { status, text } = vercelCurlRequest({
			deploymentUrl: base,
			path: '/api/paychangu/start',
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: rawBody,
		})
		let data
		try {
			data = JSON.parse(text || 'null')
		} catch {
			data = { raw: text }
		}
		return { status, data }
	}

	const url = `${base}/api/paychangu/start`
	const res = await fetch(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: rawBody,
	})
	const data = await res.json().catch(() => null)
	return { status: res.status, data }
}

function requireEnv(name) {
	const v = (process.env[name] || '').trim()
	if (!v) throw new Error(`Missing env var: ${name}`)
	return v
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

	// Prefer BASE64 when present (it avoids JSON escaping/newline pitfalls).
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
			// Some env dashboards paste JSON with raw newlines inside quoted strings (not valid JSON).
			// Try a conservative sanitizer that only escapes newlines while inside string literals.
			try {
				return JSON.parse(sanitizeJsonWithRawNewlinesInsideStrings(json))
			} catch (e) {
				throw new Error(
					'FIREBASE_SERVICE_ACCOUNT_JSON is set but not valid JSON. Prefer setting FIREBASE_SERVICE_ACCOUNT_BASE64 instead.',
				)
			}
		}
	}

	throw new Error(
		'Missing Firebase admin credentials. Set FIREBASE_SERVICE_ACCOUNT_PATH (or GOOGLE_APPLICATION_CREDENTIALS), or FIREBASE_SERVICE_ACCOUNT_JSON, or FIREBASE_SERVICE_ACCOUNT_BASE64 in .env.local.',
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

async function postPayChanguWebhook({ baseUrl, secret, uid, planId, months, countryCode }) {
	const base = baseUrl.replace(/\/$/, '')
	const payload = {
		transaction_id: `smoke-txn-${Date.now()}`,
		meta: {
			user_id: uid,
			plan_id: planId,
			months,
			country_code: countryCode,
		},
		amount: 1000,
		currency: 'MWK',
		status: 'success',
		timestamp: new Date().toISOString(),
	}
	const rawBody = JSON.stringify(payload)
	const signature = createHmac('sha256', secret).update(rawBody).digest('hex')

	if (shouldUseVercelCurl(base)) {
		const { status, text } = vercelCurlRequest({
			deploymentUrl: base,
			path: '/api/webhooks/paychangu',
			method: 'POST',
			headers: { 'content-type': 'application/json', 'x-paychangu-signature': signature },
			body: rawBody,
		})
		let data
		try {
			data = JSON.parse(text || 'null')
		} catch {
			data = { raw: text }
		}
		return { status, data }
	}

	const webhookUrl = `${base}/api/webhooks/paychangu`
	const res = await fetch(webhookUrl, {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			'x-paychangu-signature': signature,
		},
		body: rawBody,
	})
	const data = await res.json().catch(() => null)
	return { status: res.status, data }
}

async function getSubscriptionsMe({ baseUrl, idToken }) {
	const base = baseUrl.replace(/\/$/, '')
	if (shouldUseVercelCurl(base)) {
		const { status, text } = vercelCurlRequest({
			deploymentUrl: base,
			path: '/api/subscriptions/me',
			method: 'GET',
			headers: { authorization: `Bearer ${idToken}` },
		})
		let data
		try {
			data = JSON.parse(text || 'null')
		} catch {
			data = { raw: text }
		}
		return { status, data }
	}

	const url = `${base}/api/subscriptions/me`
	const res = await fetch(url, {
		headers: { authorization: `Bearer ${idToken}` },
	})
	const data = await res.json().catch(() => null)
	return { status: res.status, data }
}

function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms))
}

async function waitForActivePlan({ baseUrl, idToken, planId, timeoutMs = 7 * 60_000, intervalMs = 5_000 }) {
	const deadline = Date.now() + timeoutMs
	let last = null
	while (Date.now() < deadline) {
		const me = await getSubscriptionsMe({ baseUrl, idToken })
		last = me
		if (me.status === 200) {
			const gotPlan = String(me.data?.entitlements?.plan_id || '')
			const subStatus = String(me.data?.subscription?.status || '')
			if (gotPlan === planId && subStatus === 'active') return { ok: true, me }
		}
		await sleep(intervalMs)
	}
	return { ok: false, me: last }
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
	const webhookSecret = getEnv('PAYCHANGU_WEBHOOK_SECRET')
	const realPayChangu = String(process.env.SMOKE_REAL || '0').trim() === '1'

	const uid = (process.env.TEST_USER_ID || '').trim() || `smoke_consumer_${Date.now()}`
	const planId = (process.env.TEST_PLAN_ID || 'premium').trim()
	const initialMonths = Math.max(1, Math.min(24, Number(process.env.TEST_MONTHS_INITIAL || 1) || 1))
	const extendMonths = Math.max(1, Math.min(24, Number(process.env.TEST_MONTHS_EXTEND || process.env.TEST_MONTHS || 2) || 2))
	const doExtend = String(process.env.SMOKE_EXTEND || '1').trim() !== '0'
	const countryCode = (process.env.TEST_COUNTRY_CODE || 'MW').trim()

	console.log(`Base URL: ${baseUrl}`)
	console.log(`UID: ${uid}`)
	console.log(`Plan: ${planId} (initial=${initialMonths} months, extend=${extendMonths} months) Country: ${countryCode}`)
	if (process.env.TEST_USER_ID) console.log('Note: using provided TEST_USER_ID (stable across runs).')
	if (!apiKey) console.log('Note: NEXT_PUBLIC_FIREBASE_API_KEY not set; will skip ID-token exchange.')
	if (!webhookSecret) console.log('Note: PAYCHANGU_WEBHOOK_SECRET not set; will skip webhook simulation.')

	let idToken = null
	let canAuth = true
	let checkoutUrl = null
	let txRef = null

	// 0) Verify checkout URL configuration (PayChangu start endpoint).
	if (String(process.env.SMOKE_SKIP_START || '0').trim() !== '1') {
		const start = await postPayChanguStart({ baseUrl, uid, planId, months: initialMonths, countryCode })
		console.log(`[0] POST /api/paychangu/start => ${start.status}`)
		if (start.status !== 200) {
			const startErr = String(start.data?.error || '')
			const isMissingConfig = start.status === 503 && startErr.toLowerCase().includes('missing paychangu configuration')
			if (!realPayChangu && isMissingConfig) {
				console.warn('[0x] /api/paychangu/start not configured; continuing with webhook smoke only.')
				console.warn('     Set PAYCHANGU_CHECKOUT_URL (or PAYCHANGU_SECRET_KEY) to enable full start-checkout testing.')
			} else {
				console.log(start.data)
				throw new Error('paychangu/start did not succeed')
			}
		} else {
		checkoutUrl = String(start.data?.checkout_url || '')
		txRef = start.data?.tx_ref ? String(start.data.tx_ref) : null
		if (!String(checkoutUrl || '').trim()) {
			console.log(start.data)
			throw new Error('Missing checkout_url in paychangu/start response')
		}
		const mode = start.data?.mode ? String(start.data.mode) : 'unknown'
		console.log(`[0a] checkout_url: ${checkoutUrl}`)
		if (txRef) console.log(`[0b] tx_ref: ${txRef}`)
		console.log(`[0c] mode: ${mode}`)
		if (realPayChangu && mode !== 'api') {
			console.warn('⚠️ SMOKE_REAL=1 but server returned non-api mode. Ensure PAYCHANGU_SECRET_KEY is set on the deployment.')
		}
		}
	}

	// 1) Mint an ID token like the consumer app would have.
	if (!apiKey) {
		canAuth = false
		console.log('[1] Skipped Firebase ID token (missing NEXT_PUBLIC_FIREBASE_API_KEY)')
	} else {
		try {
			const auth = getFirebaseAdminAuth()
			const customToken = await auth.createCustomToken(uid)
			idToken = await exchangeCustomTokenForIdToken({ apiKey, customToken })
			console.log('[1] Firebase ID token OK')
		} catch (e) {
			canAuth = false
			console.log(`[1] Skipped Firebase ID token (${e?.message ?? e})`)
		}
	}

	// 2) Webhook: use test webhook (default) or wait for real PayChangu webhook.
	let webhookOk = false
	if (realPayChangu) {
		console.log('[2] Real mode enabled: complete the payment in the PayChangu checkout link.')
		if (checkoutUrl) console.log(`[2a] Open checkout_url in a browser and pay: ${checkoutUrl}`)
		if (txRef) console.log(`[2b] Track tx_ref: ${txRef}`)
		console.log('[2c] Waiting for PayChangu to POST the webhook and activate the subscription...')
		if (!idToken) {
			console.log('[2d] Cannot poll /api/subscriptions/me without Firebase ID token.')
			console.log('    You can verify in Supabase SQL editor:')
			console.log(`    - select * from public.user_subscriptions where user_id='${uid}' order by created_at desc limit 5;`)
			if (txRef) {
				console.log(
					`    - select * from public.subscription_payments where provider='paychangu' and (provider_reference='${txRef}' or raw::text ilike '%${txRef}%') order by created_at desc limit 20;`,
				)
			}
			console.log('⚠️ Partial smoke only (real checkout started; webhook verification requires DB check).')
			return
		}

		const wait = await waitForActivePlan({
			baseUrl,
			idToken,
			planId,
			timeoutMs: Math.max(30_000, Number(process.env.SMOKE_REAL_TIMEOUT_MS || 7 * 60_000) || 7 * 60_000),
			intervalMs: Math.max(1_000, Number(process.env.SMOKE_REAL_POLL_MS || 5_000) || 5_000),
		})
		if (!wait.ok) {
			console.log(wait.me?.data)
			throw new Error('Timed out waiting for real PayChangu webhook to activate subscription')
		}
		console.log('[2e] Subscription activated (real webhook observed via /api/subscriptions/me).')
		webhookOk = true
	} else {
		if (!webhookSecret) {
			console.log('[2] Skipped PayChangu webhook (missing PAYCHANGU_WEBHOOK_SECRET)')
		} else {
			const webhook = await postPayChanguWebhook({ baseUrl, secret: webhookSecret, uid, planId, months: initialMonths, countryCode })
			console.log(`[2] PayChangu webhook => ${webhook.status}`)
			if (webhook.status !== 200) {
				console.log(webhook.data)
				throw new Error('Webhook did not succeed')
			}
			webhookOk = true
		}
	}

	// 3) Consumer reads subscription.
	if (!idToken) {
		const url = `${baseUrl.replace(/\/$/, '')}/api/subscriptions/me`
		const res = await fetch(url)
		const data = await res.json().catch(() => null)
		console.log(`[3] GET /api/subscriptions/me (unauth) => ${res.status}`)
		if (res.status !== 401) {
			console.log(data)
			console.warn('Warning: expected 401 when unauthenticated')
		}
		console.log('⚠️ Partial smoke only (no Firebase ID token available).')
		return
	}

	if (!webhookOk) {
		const me = await getSubscriptionsMe({ baseUrl, idToken })
		console.log(`[3] GET /api/subscriptions/me (auth) => ${me.status}`)
		if (me.status !== 200) {
			console.log(me.data)
			console.warn('⚠️ Auth works, but subscription not validated (webhook not run).')
			return
		}
		console.log('⚠️ Partial smoke only (auth OK; webhook step skipped).')
		return
	}

	const me = await getSubscriptionsMe({ baseUrl, idToken })
	console.log(`[3] GET /api/subscriptions/me => ${me.status}`)
	if (me.status !== 200) {
		console.log(me.data)
		throw new Error('subscriptions/me did not succeed')
	}

	const gotPlan = String(me.data?.entitlements?.plan_id || '')
	if (gotPlan !== planId) {
		console.log(me.data)
		throw new Error(`Expected entitlements.plan_id=${planId}, got ${gotPlan}`)
	}

	const endsAt1Raw = me.data?.subscription?.ends_at
	if (!endsAt1Raw) {
		console.log(me.data)
		throw new Error('Expected subscription.ends_at to be set after paid webhook')
	}
	const endsAt1 = new Date(String(endsAt1Raw))
	if (Number.isNaN(endsAt1.getTime())) {
		console.log(me.data)
		throw new Error(`Invalid subscription.ends_at: ${String(endsAt1Raw)}`)
	}

	console.log(`[3a] ends_at after payment: ${endsAt1.toISOString()}`)

	if (doExtend) {
		// 4) Trigger a second paid webhook for the same user/plan and verify ends_at extends.
		const webhook2 = await postPayChanguWebhook({ baseUrl, secret: webhookSecret, uid, planId, months: extendMonths, countryCode })
		console.log(`[4] PayChangu webhook (extend) => ${webhook2.status}`)
		if (webhook2.status !== 200) {
			console.log(webhook2.data)
			throw new Error('Extend webhook did not succeed')
		}

		const me2 = await getSubscriptionsMe({ baseUrl, idToken })
		console.log(`[5] GET /api/subscriptions/me (after extend) => ${me2.status}`)
		if (me2.status !== 200) {
			console.log(me2.data)
			throw new Error('subscriptions/me (after extend) did not succeed')
		}

		const endsAt2Raw = me2.data?.subscription?.ends_at
		if (!endsAt2Raw) {
			console.log(me2.data)
			throw new Error('Expected subscription.ends_at after extend webhook')
		}
		const endsAt2 = new Date(String(endsAt2Raw))
		if (Number.isNaN(endsAt2.getTime())) {
			console.log(me2.data)
			throw new Error(`Invalid subscription.ends_at after extend: ${String(endsAt2Raw)}`)
		}

		console.log(`[5a] ends_at after extend: ${endsAt2.toISOString()}`)
		if (!(endsAt2.getTime() > endsAt1.getTime())) {
			throw new Error('Expected ends_at to increase after extend webhook')
		}
	}

	console.log('✅ Subscription flow works end-to-end (webhook -> /me)')
}

main().catch((err) => {
	console.error('❌ Subscription smoke test failed:', err?.message || err)
	process.exit(1)
})
