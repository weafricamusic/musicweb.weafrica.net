import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

function readTextIfExists(filePath) {
	try {
		return fs.readFileSync(filePath, 'utf8')
	} catch {
		return null
	}
}

function writeText(filePath, content) {
	fs.mkdirSync(path.dirname(filePath), { recursive: true })
	fs.writeFileSync(filePath, content, 'utf8')
}

function parseEnvLines(lines) {
	/** @type {Map<string, { index: number, rawValue: string }>} */
	const map = new Map()
	for (let index = 0; index < lines.length; index++) {
		const line = lines[index]
		if (!line) continue
		const trimmed = line.trimStart()
		if (trimmed.startsWith('#')) continue
		const match = trimmed.match(/^([A-Z0-9_]+)\s*=(.*)$/)
		if (!match) continue
		const key = match[1]
		const rawValue = match[2] ?? ''
		map.set(key, { index, rawValue })
	}
	return map
}

function upsertEnvValue(lines, envIndex, key, value, { force = false } = {}) {
	const existing = envIndex.get(key)
	if (existing) {
		const current = (existing.rawValue ?? '').trim()
		if (!force && current) return { changed: false, action: 'kept-existing' }
		lines[existing.index] = `${key}=${value}`
		return { changed: true, action: current ? 'overwrote' : 'filled-empty' }
	}

	lines.push(`${key}=${value}`)
	return { changed: true, action: 'added' }
}

function maskKey(value) {
	if (!value) return '<empty>'
	const trimmed = String(value).trim()
	if (trimmed.length <= 8) return '********'
	return `${trimmed.slice(0, 4)}…${trimmed.slice(-4)}`
}

function getAndroidFirebaseWebConfig({ adminRoot }) {
	const googleServicesPath = path.resolve(adminRoot, '..', 'android', 'app', 'google-services.json')
	const raw = readTextIfExists(googleServicesPath)
	if (!raw) {
		return {
			ok: false,
			googleServicesPath,
			error:
				'Could not find android/app/google-services.json. If you do not commit it, set NEXT_PUBLIC_FIREBASE_* manually in .env.local.',
		}
	}

	let json
	try {
		json = JSON.parse(raw)
	} catch {
		return {
			ok: false,
			googleServicesPath,
			error: 'android/app/google-services.json is not valid JSON.',
		}
	}

	const projectId = json?.project_info?.project_id
	const apiKey = json?.client?.[0]?.api_key?.[0]?.current_key

	if (!projectId || !apiKey) {
		return {
			ok: false,
			googleServicesPath,
			error:
				'Could not extract project_id/api_key from android/app/google-services.json. Set NEXT_PUBLIC_FIREBASE_API_KEY, NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN, NEXT_PUBLIC_FIREBASE_PROJECT_ID manually.',
		}
	}

	return {
		ok: true,
		googleServicesPath,
		projectId,
		apiKey,
		authDomain: `${projectId}.firebaseapp.com`,
	}
}

function ensureTrailingNewline(text) {
	return text.endsWith('\n') ? text : `${text}\n`
}

function main() {
	const scriptDir = path.dirname(fileURLToPath(import.meta.url))
	const adminRoot = path.resolve(scriptDir, '..')
	const envExamplePath = path.join(adminRoot, '.env.example')
	const envLocalPath = path.join(adminRoot, '.env.local')

	const force = process.argv.includes('--force')

	const exampleText = readTextIfExists(envExamplePath)
	if (!exampleText) {
		console.error('Missing .env.example. Cannot bootstrap .env.local.')
		process.exitCode = 1
		return
	}

	let envLocalText = readTextIfExists(envLocalPath)
	let created = false
	if (!envLocalText) {
		envLocalText = exampleText
		created = true
	}

	let lines = envLocalText.split(/\r?\n/)
	// If file ended with newline, split creates a final empty string line.
	// We'll preserve it by normalizing at write-time.

	let envIndex = parseEnvLines(lines)
	const changes = []

	const androidConfig = getAndroidFirebaseWebConfig({ adminRoot })
	if (!androidConfig.ok) {
		console.warn(`[setup:env] ${androidConfig.error}`)
		console.warn(`[setup:env] Looked for: ${androidConfig.googleServicesPath}`)
	} else {
		const set1 = upsertEnvValue(lines, envIndex, 'NEXT_PUBLIC_FIREBASE_PROJECT_ID', androidConfig.projectId, { force })
		if (set1.changed) changes.push(`NEXT_PUBLIC_FIREBASE_PROJECT_ID (${set1.action})`)
		const set2 = upsertEnvValue(lines, envIndex, 'NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN', androidConfig.authDomain, { force })
		if (set2.changed) changes.push(`NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN (${set2.action})`)
		const set3 = upsertEnvValue(lines, envIndex, 'NEXT_PUBLIC_FIREBASE_API_KEY', androidConfig.apiKey, { force })
		if (set3.changed) changes.push(`NEXT_PUBLIC_FIREBASE_API_KEY (${set3.action}, ${maskKey(androidConfig.apiKey)})`)
		const set4 = upsertEnvValue(lines, envIndex, 'FIREBASE_PROJECT_ID', androidConfig.projectId, { force })
		if (set4.changed) changes.push(`FIREBASE_PROJECT_ID (${set4.action})`)
	}

	// Admin allowlist/guard cookie
	const setBackend = upsertEnvValue(lines, envIndex, 'ADMIN_BACKEND_BASE_URL', 'http://127.0.0.1:3000', { force })
	if (setBackend.changed) changes.push(`ADMIN_BACKEND_BASE_URL (${setBackend.action})`)

	const setEmails = upsertEnvValue(lines, envIndex, 'ADMIN_EMAILS', 'admin@weafrica.test', { force })
	if (setEmails.changed) changes.push(`ADMIN_EMAILS (${setEmails.action})`)

	if (!envIndex.get('ADMIN_GUARD_SECRET') || !String(envIndex.get('ADMIN_GUARD_SECRET')?.rawValue ?? '').trim() || force) {
		const secret = crypto.randomBytes(32).toString('hex')
		const setSecret = upsertEnvValue(lines, envIndex, 'ADMIN_GUARD_SECRET', secret, { force: true })
		if (setSecret.changed) changes.push(`ADMIN_GUARD_SECRET (${setSecret.action}, ${maskKey(secret)})`)
	}

	// Ensure we have a sensible default local path (file is still required).
	const setSaPath = upsertEnvValue(lines, envIndex, 'FIREBASE_SERVICE_ACCOUNT_PATH', './firebase-service-account.json', { force: false })
	if (setSaPath.changed) changes.push(`FIREBASE_SERVICE_ACCOUNT_PATH (${setSaPath.action})`)

	// Re-index after modifications in case we added new keys.
	lines = lines.filter((l, idx, arr) => {
		// keep all lines; just ensure we don't accumulate extra trailing empty lines
		return idx < arr.length - 1 || l !== ''
	})
	const output = ensureTrailingNewline(lines.join('\n'))
	writeText(envLocalPath, output)

	console.log(created ? '[setup:env] Created .env.local from .env.example' : '[setup:env] Updated .env.local')
	if (changes.length) {
		console.log('[setup:env] Applied:')
		for (const c of changes) console.log(` - ${c}`)
	} else {
		console.log('[setup:env] No changes needed.')
	}

	console.log('[setup:env] Next steps:')
	console.log(' - Restart the admin dev server: npm run admin (repo root)')
	console.log('   - Or: npm --prefix admin_dashboard run dev')
	console.log(' - Ensure Firebase Admin is configured for /api/auth/session:')
	console.log('   - Download a service account JSON key from Firebase Console → Project settings → Service accounts')
	console.log('   - Save it as firebase-service-account.json, or run:')
	console.log('     - Repo root: npm run admin:setup:firebase-admin -- --from-clipboard (macOS) / --from <path>')
	console.log('     - Or (admin_dashboard): npm run setup:firebase-admin -- --from-clipboard (macOS) / --from <path>')
}

main()
