import fs from 'node:fs'
import cp from 'node:child_process'
import dotenv from 'dotenv'

const envFile = '.env.local'

const argv = process.argv.slice(2)
const allowMissingRequired = argv.includes('--allow-missing-required') || argv.includes('--allow-missing')

function getVercelScope() {
	try {
		const raw = fs.readFileSync('.vercel/project.json', 'utf8')
		const json = JSON.parse(raw)
		const orgId = typeof json?.orgId === 'string' ? json.orgId : null
		return orgId && orgId.length ? orgId : null
	} catch {
		return null
	}
}

function mustGet(parsed, key) {
	const value = maybeGet(parsed, key)
	if (value) return value
	if (allowMissingRequired) {
		process.stdout.write(`WARN Missing required ${key} in ${envFile}; skipping.\n`)
		return null
	}
	throw new Error(`Missing ${key} in ${envFile} (set a non-empty value)`)
}

function maybeGet(parsed, key) {
	const value = parsed[key]
	if (!value) return null
	const trimmed = String(value).trim()
	return trimmed.length ? trimmed : null
}

function setEnvVar(name, targetEnv, value, { sensitive }) {
	const args = ['env', 'add', name, targetEnv, '--force']
	if (sensitive) args.push('--sensitive')
	const scope = getVercelScope()
	if (scope) args.push('--scope', scope)
	const res = cp.spawnSync('vercel', args, {
		input: value + '\n',
		stdio: ['pipe', 'pipe', 'pipe'],
		encoding: 'utf8',
	})
	if (res.status !== 0) {
		throw new Error(
			[
				`Failed setting ${name} (${targetEnv}).`,
				(res.stdout ?? '').trim(),
				(res.stderr ?? '').trim(),
			]
				.filter(Boolean)
				.join('\n'),
		)
	}
	process.stdout.write(`OK ${targetEnv} ${name}\n`)
}

const parsed = dotenv.parse(fs.readFileSync(envFile))

const nonSensitiveKeys = [
	'NEXT_PUBLIC_FIREBASE_API_KEY',
	'NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN',
	'NEXT_PUBLIC_FIREBASE_PROJECT_ID',
	'NEXT_PUBLIC_SUPABASE_URL',
	'NEXT_PUBLIC_SUPABASE_ANON_KEY',
	'ADMIN_EMAILS',
]

const optionalNonSensitiveKeys = [
	// Optional Firebase client config
	'NEXT_PUBLIC_FIREBASE_APP_ID',
	'NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID',
	'NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET',

	'NEXT_PUBLIC_SENTRY_DSN',
	'SENTRY_TRACES_SAMPLE_RATE',
	'SENTRY_REPLAYS_SESSION_SAMPLE_RATE',
	'SENTRY_REPLAYS_ON_ERROR_SAMPLE_RATE',

	// PayChangu (server-only but not sensitive)
	'PAYCHANGU_CALLBACK_URL',
	'PAYCHANGU_RETURN_URL',
	'PAYCHANGU_CURRENCY',
]

const sensitiveKeys = ['ADMIN_GUARD_SECRET', 'SUPABASE_SERVICE_ROLE_KEY']

const optionalSensitiveKeys = [
	// Monitoring
	'SENTRY_DSN',

	// Push
	'PUSH_INTERNAL_SECRET',

	// Webhooks / cron
	'PAYCHANGU_SECRET_KEY',
	'PAYCHANGU_WEBHOOK_SECRET',
	'SUBSCRIPTIONS_CRON_SECRET',

	// Risk tools
	'RISK_SCAN_SECRET',

	// Live streaming (Agora)
	'AGORA_APP_ID',
	'AGORA_CUSTOMER_ID',
	'AGORA_CUSTOMER_SECRET',
	'LIVE_STREAM_STOP_WEBHOOK_URL',
	'LIVE_STREAM_STOP_WEBHOOK_SECRET',
]

let firebaseServiceAccountBase64 = null
try {
	const path = parsed.FIREBASE_SERVICE_ACCOUNT_PATH || 'firebase-service-account.json'
	if (fs.existsSync(path)) {
		firebaseServiceAccountBase64 = fs.readFileSync(path).toString('base64')
	}
} catch {
	// ignore
}

const targets = ['preview', 'production']
for (const target of targets) {
	for (const key of nonSensitiveKeys) {
		const value = mustGet(parsed, key)
		if (value) setEnvVar(key, target, value, { sensitive: false })
		else process.stdout.write(`SKIP ${target} ${key} (missing required)\n`)
	}
	for (const key of optionalNonSensitiveKeys) {
		const value = maybeGet(parsed, key)
		if (value) setEnvVar(key, target, value, { sensitive: false })
		else process.stdout.write(`SKIP ${target} ${key} (not set)\n`)
	}
	for (const key of sensitiveKeys) {
		const value = mustGet(parsed, key)
		if (value) setEnvVar(key, target, value, { sensitive: true })
		else process.stdout.write(`SKIP ${target} ${key} (missing required)\n`)
	}
	for (const key of optionalSensitiveKeys) {
		const value = maybeGet(parsed, key)
		if (value) setEnvVar(key, target, value, { sensitive: true })
		else process.stdout.write(`SKIP ${target} ${key} (not set)\n`)
	}
	if (firebaseServiceAccountBase64) {
		setEnvVar('FIREBASE_SERVICE_ACCOUNT_BASE64', target, firebaseServiceAccountBase64, { sensitive: true })
	} else {
		process.stdout.write(`WARN ${target} FIREBASE_SERVICE_ACCOUNT_BASE64 not set (service account file missing)\n`)
	}
}

process.stdout.write('Done.\n')
