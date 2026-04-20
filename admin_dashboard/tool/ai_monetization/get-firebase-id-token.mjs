#!/usr/bin/env node
import dotenv from 'dotenv'

// Load local env first (preferred for dev).
dotenv.config({ path: '.env.local' })
dotenv.config({ path: '.env' })

await main()

async function main() {
	const apiKey = firstNonEmpty(
		process.env.FIREBASE_WEB_API_KEY,
		process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
		process.env.FIREBASE_API_KEY,
	)
	const email = firstNonEmpty(process.env.FIREBASE_EMAIL, process.argv[2])
	const password = firstNonEmpty(process.env.FIREBASE_PASSWORD, process.argv[3])

	if (!apiKey) {
		console.error('Missing FIREBASE_WEB_API_KEY (or NEXT_PUBLIC_FIREBASE_API_KEY in .env.local).')
		process.exit(2)
	}
	if (!email || !password) {
		console.error('Usage: node tool/ai_monetization/get-firebase-id-token.mjs <email> <password>')
		console.error('Or set env: FIREBASE_EMAIL and FIREBASE_PASSWORD')
		process.exit(2)
	}

	const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`
	const res = await fetch(url, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ email, password, returnSecureToken: true }),
	})

	const json = await res.json().catch(() => null)
	if (!res.ok) {
		const msg = json?.error?.message || json?.error || JSON.stringify(json) || `HTTP ${res.status}`
		console.error(`Failed to sign in: ${msg}`)
		process.exit(1)
	}

	const token = String(json?.idToken || '').trim()
	if (!token) {
		console.error('No idToken returned from Firebase.')
		process.exit(1)
	}

	// Print token only (so callers can do: ID_TOKEN="$(node ...)" )
	process.stdout.write(token)
}

function firstNonEmpty(...values) {
	for (const v of values) {
		if (typeof v !== 'string') continue
		const t = v.trim()
		if (t) return t
	}
	return ''
}
