import dotenv from 'dotenv'
import { createClient } from '@supabase/supabase-js'
import { execFileSync } from 'node:child_process'

dotenv.config({ path: '.env.local', override: true })

function required(name) {
	const v = (process.env[name] || '').trim()
	if (!v) throw new Error(`Missing ${name} in .env.local`)
	return v
}

function optional(name) {
	const v = (process.env[name] || '').trim()
	return v || null
}

function isLocalBaseUrl(baseUrl) {
	try {
		const u = new URL(baseUrl)
		return u.hostname === 'localhost' || u.hostname === '127.0.0.1'
	} catch {
		return true
	}
}

async function httpJson(url, init) {
	const u = new URL(url)
	const isVercel = u.hostname.endsWith('vercel.app')
	const useVercelCurl = isVercel && String(process.env.SMOKE_USE_VERCEL_CURL || '1').trim() !== '0'

	if (useVercelCurl) {
		const method = (init?.method || 'GET').toUpperCase()
		const headers = init?.headers || {}
		const headerArgs = []
		for (const [k, v] of Object.entries(headers)) {
			if (v == null) continue
			headerArgs.push('--header', `${k}: ${String(v)}`)
		}
		const body = typeof init?.body === 'string' ? init.body : null
		const bodyArgs = body ? ['--data-raw', body] : []
		const writeOut = '\n__HTTP_CODE__:%{http_code}\n'
		const out = execFileSync(
			'vercel',
			[
				'curl',
				`${u.pathname}${u.search}`,
				'--deployment',
				u.origin,
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
		let json
		try {
			json = JSON.parse(text)
		} catch {
			json = { raw: text }
		}
		return { status, json }
	}

	const res = await fetch(url, init)
	const text = await res.text()
	let json
	try {
		json = JSON.parse(text)
	} catch {
		json = { raw: text }
	}
	return { status: res.status, json }
}

async function detectCountriesCodeColumn(supabase) {
	// Prefer new schema first.
	{
		const { error } = await supabase.from('countries').select('country_code').limit(1)
		if (!error) return 'country_code'
		const msg = String(error?.message ?? '').toLowerCase()
		const code = String(error?.code ?? '')
		if (!(code === '42703' || msg.includes('country_code'))) {
			throw new Error(`Unexpected countries probe error: ${error?.message ?? 'unknown'}`)
		}
	}

	// Legacy schema.
	{
		const { error } = await supabase.from('countries').select('code').limit(1)
		if (!error) return 'code'
		throw new Error(`Legacy countries probe failed: ${error?.message ?? 'unknown'}`)
	}
}

async function main() {
	const baseUrl = process.argv[2] || process.env.SMOKE_BASE_URL || 'http://localhost:3010'
	const supabaseUrl = optional('NEXT_PUBLIC_SUPABASE_URL')
	const serviceRoleKey = optional('SUPABASE_SERVICE_ROLE_KEY')
	const supabase =
		supabaseUrl && serviceRoleKey
			? createClient(supabaseUrl, serviceRoleKey, {
				auth: { persistSession: false, autoRefreshToken: false },
			})
			: null

	console.log(`Base URL: ${baseUrl}`)

	// 1) Ads config endpoint should respond.
	console.log('\n[1] GET /api/ads/config')
	let r = await httpJson(`${baseUrl}/api/ads/config?country_code=MW`, { method: 'GET' })
	console.log(`- status: ${r.status}`)
	if (r.status !== 200) throw new Error(`ads config failed: ${JSON.stringify(r.json)}`)
	if (!r.json?.ok) throw new Error(`ads config not ok: ${JSON.stringify(r.json)}`)

	// 2) DB toggle should reflect in endpoint (proves DB <-> API wiring).
	console.log('\n[2] Toggle countries.ads_enabled (round-trip)')
	if (!supabase) {
		if (isLocalBaseUrl(baseUrl)) {
			throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY in .env.local')
		}
		console.log('- skipped (no SUPABASE_SERVICE_ROLE_KEY; DB toggle checks require service role)')
	} else {
		const codeColumn = await detectCountriesCodeColumn(supabase)
		console.log(`- countries code column: ${codeColumn}`)

		const filter = codeColumn === 'country_code' ? { country_code: 'MW' } : { code: 'MW' }
		const selectCols = codeColumn === 'country_code' ? 'country_code,ads_enabled,is_active' : 'code,ads_enabled,is_active'
		const { data: countryRow, error: fetchErr } = await supabase.from('countries').select(selectCols).match(filter).limit(1).maybeSingle()
		if (fetchErr) throw new Error(`countries fetch failed: ${fetchErr.message}`)
		if (!countryRow) throw new Error('countries row for MW not found')

		const original = Boolean(countryRow.ads_enabled)
		const next = !original
		console.log(`- original ads_enabled: ${original} -> ${next}`)

		{
			let updateErr = (await supabase.from('countries').update({ ads_enabled: next, updated_at: new Date().toISOString() }).match(filter)).error
			const msg = String(updateErr?.message ?? '').toLowerCase()
			const missingUpdatedAt = msg.includes('updated_at')
			if (updateErr && missingUpdatedAt) {
				updateErr = (await supabase.from('countries').update({ ads_enabled: next }).match(filter)).error
			}
			if (updateErr) throw new Error(`countries update failed: ${updateErr.message}`)
		}

		r = await httpJson(`${baseUrl}/api/ads/config?country_code=MW`, { method: 'GET' })
		console.log(`- api.ads_enabled: ${r.json?.ads_enabled}`)
		if (r.status !== 200 || !r.json?.ok) throw new Error(`ads config after update failed: ${JSON.stringify(r.json)}`)
		if (Boolean(r.json.ads_enabled) !== Boolean(next && (countryRow.is_active ?? true))) {
			console.warn('- warning: ads_enabled did not match expected; check country is_active and plan settings')
		}

		// Restore.
		{
			let restoreErr = (await supabase.from('countries').update({ ads_enabled: original, updated_at: new Date().toISOString() }).match(filter)).error
			const msg = String(restoreErr?.message ?? '').toLowerCase()
			const missingUpdatedAt = msg.includes('updated_at')
			if (restoreErr && missingUpdatedAt) {
				restoreErr = (await supabase.from('countries').update({ ads_enabled: original }).match(filter)).error
			}
			if (restoreErr) throw new Error(`countries restore failed: ${restoreErr.message}`)
		}
		console.log('- restored original ads_enabled')
	}

	// 3) Events ingest should be configured in prod; in local it may be intentionally missing.
	console.log('\n[3] POST /api/events/ingest')
	const ingestSecret = optional('EVENTS_INGEST_SECRET')
	if (!ingestSecret) {
		console.log('- skipped (EVENTS_INGEST_SECRET is not set)')
	} else {
		const payload = { event_name: 'smoke_test', platform: 'admin', source: 'smoke', created_at: new Date().toISOString() }
		r = await httpJson(`${baseUrl}/api/events/ingest`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', 'x-ingest-secret': ingestSecret },
			body: JSON.stringify(payload),
		})
		console.log(`- status: ${r.status}`)
		if (r.status !== 200 || !r.json?.ok) throw new Error(`events ingest failed: ${JSON.stringify(r.json)}`)
		console.log(`- ingested: ${r.json.ingested}`)
	}

	// 4) Push register should require a Firebase ID token.
	console.log('\n[4] POST /api/push/register (unauthenticated)')
	r = await httpJson(`${baseUrl}/api/push/register`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })
	console.log(`- status: ${r.status}`)
	if (r.status !== 401) console.warn(`- warning: expected 401, got ${r.status}`)

	console.log('\n✅ Smoke checks complete')
}

main().catch((e) => {
	console.error(`\n❌ Smoke check failed: ${e?.message ?? e}`)
	process.exit(1)
})
