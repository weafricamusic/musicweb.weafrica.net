#!/usr/bin/env node

/**
 * Minimal smoke test for the PayChangu start endpoint.
 *
 * Usage:
 *   node scripts/test-paychangu-start.mjs --base https://<ref>.functions.supabase.co --method POST --plan pro --user test --months 1
 *   node scripts/test-paychangu-start.mjs --base https://<ref>.functions.supabase.co --method GET  --plan pro --user test --months 1
 */

function readArg(name, fallback = null) {
	const ix = process.argv.indexOf(`--${name}`)
	if (ix === -1) return fallback
	return process.argv[ix + 1] ?? fallback
}

const base = readArg('base', process.env.WEAFRICA_API_BASE_URL || process.env.API_BASE_URL)
const method = String(readArg('method', 'POST')).toUpperCase()
const planId = readArg('plan', 'pro')
const userId = readArg('user', 'test')
const months = Number(readArg('months', '1'))
const countryCode = readArg('country', 'MW')
const token = readArg('token', process.env.WEAFRICA_FIREBASE_ID_TOKEN || process.env.FIREBASE_ID_TOKEN)

if (!base) {
	console.error('Missing --base (or WEAFRICA_API_BASE_URL)')
	process.exit(2)
}

const url = new URL('/api/paychangu/start', base)

async function main() {
	let res
	const headers = token ? { authorization: `Bearer ${token}` } : {}
	if (method === 'GET') {
		url.searchParams.set('plan_id', planId)
		url.searchParams.set('user_id', userId)
		url.searchParams.set('months', String(months))
		url.searchParams.set('country_code', countryCode)
		res = await fetch(url.toString(), { method: 'GET', headers })
	} else if (method === 'POST') {
		res = await fetch(url.toString(), {
			method: 'POST',
			headers: { 'content-type': 'application/json', ...headers },
			body: JSON.stringify({ plan_id: planId, user_id: userId, months, country_code: countryCode }),
		})
	} else {
		console.error(`Unsupported --method ${method}`)
		process.exit(2)
	}

	const text = await res.text().catch(() => '')
	let json = null
	try {
		json = text ? JSON.parse(text) : null
	} catch {
		json = { raw: text }
	}

	console.log(`HTTP ${res.status}`)
	console.log(JSON.stringify(json, null, 2))
	process.exit(res.ok ? 0 : 1)
}

main().catch((e) => {
	console.error(e)
	process.exit(1)
})
