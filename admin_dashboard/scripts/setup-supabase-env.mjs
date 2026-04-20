import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

function usage() {
	console.log(
		[
			'Usage:',
			'  npm --prefix admin_dashboard run setup:supabase',
			'  npm --prefix admin_dashboard run setup:supabase -- --service-from-clipboard   # macOS pbpaste',
			'  npm --prefix admin_dashboard run setup:supabase -- --service-from <path-to-key.txt>',
			'  npm --prefix admin_dashboard run setup:supabase -- --service-from-stdin',
			'',
			'What it does:',
			'- Fills NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local by copying from existing local Flutter config (tool/supabase.env.json or assets/config/supabase.env.json) when present.',
			'- Optionally sets SUPABASE_SERVICE_ROLE_KEY (server-only) from clipboard/file/stdin.',
			'- Validates JWT roles (anon vs service_role) and warns on ref mismatches.',
		].join('\n'),
	)
}

function getArgValue(flag) {
	const idx = process.argv.indexOf(flag)
	if (idx === -1) return null
	const next = process.argv[idx + 1]
	return typeof next === 'string' && next.trim() ? next.trim() : null
}

function hasFlag(flag) {
	return process.argv.includes(flag)
}

function readTextIfExists(filePath) {
	try {
		return fs.readFileSync(filePath, 'utf8')
	} catch {
		return null
	}
}

function readJsonIfExists(filePath) {
	const raw = readTextIfExists(filePath)
	if (!raw) return null
	try {
		return JSON.parse(raw)
	} catch {
		return null
	}
}

function ensureTrailingNewline(text) {
	return text.endsWith('\n') ? text : `${text}\n`
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

function looksLikePlaceholder(value) {
	if (!value) return true
	const v = String(value).trim().toLowerCase()
	return (
		v === '' ||
		v.includes('your_project_ref') ||
		v.includes('your_supabase_anon') ||
		v.includes('yourservicerolekey') ||
		v.includes('placeholder') ||
		v.includes('...')
	)
}

function normalizeEnvValue(value) {
	return String(value ?? '')
		.trim()
		.replace(/^['"]|['"]$/g, '')
		.replace(/\\r/g, '')
		.replace(/\\n/g, '')
		.replace(/\s+/g, '')
}

function normalizeSupabaseUrl(value) {
	const compact = normalizeEnvValue(value)
	if (!compact) return null
	if (compact.startsWith('http://') || compact.startsWith('https://')) return compact
	if (/^[a-z0-9-]+\.supabase\.(co|in)$/i.test(compact)) return `https://${compact}`
	return compact
}

function maskToken(value) {
	const v = String(value ?? '').trim()
	if (!v) return '<empty>'
	if (v.length <= 12) return '********'
	return `${v.slice(0, 4)}…${v.slice(-4)}`
}

function base64UrlDecode(input) {
	const normalized = input.replace(/-/g, '+').replace(/_/g, '/')
	const padLen = (4 - (normalized.length % 4)) % 4
	const padded = normalized + '='.repeat(padLen)
	return Buffer.from(padded, 'base64').toString('utf8')
}

function tryParseJwtPayload(value) {
	const parts = String(value || '').split('.')
	if (parts.length !== 3) return null
	try {
		const json = base64UrlDecode(parts[1] ?? '')
		const payload = JSON.parse(json)
		return payload && typeof payload === 'object' ? payload : null
	} catch {
		return null
	}
}

function classifySupabaseKey(value) {
	const compact = normalizeEnvValue(value)
	if (!compact) return { ok: false, reason: 'empty' }
	const payload = tryParseJwtPayload(compact)
	if (!payload) return { ok: false, reason: 'not-jwt' }
	const role = typeof payload.role === 'string' ? payload.role : null
	const ref = typeof payload.ref === 'string' ? payload.ref : null
	return { ok: true, value: compact, role, ref }
}

function upsertEnvValue(lines, envIndex, key, value, { force = false } = {}) {
	const existing = envIndex.get(key)
	if (existing) {
		const current = (existing.rawValue ?? '').trim()
		if (!force && current && !looksLikePlaceholder(current)) return { changed: false, action: 'kept-existing' }
		lines[existing.index] = `${key}=${value}`
		return { changed: true, action: current ? 'overwrote' : 'filled-empty' }
	}
	lines.push(`${key}=${value}`)
	return { changed: true, action: 'added' }
}

async function readStdin() {
	const chunks = []
	for await (const chunk of process.stdin) chunks.push(chunk)
	return Buffer.concat(chunks).toString('utf8')
}

function readServiceRoleFromInput() {
	if (hasFlag('--service-from-clipboard')) {
		if (process.platform !== 'darwin') {
			throw new Error('--service-from-clipboard is only supported on macOS (uses pbpaste)')
		}
		return execFileSync('pbpaste', { encoding: 'utf8' })
	}

	const fromPath = getArgValue('--service-from')
	if (fromPath) {
		const resolved = path.isAbsolute(fromPath) ? fromPath : path.resolve(process.cwd(), fromPath)
		const raw = readTextIfExists(resolved)
		if (!raw) throw new Error(`Service-role key file not found: ${resolved}`)
		return raw
	}

	if (hasFlag('--service-from-stdin')) {
		// Caller will await stdin in main.
		return '__READ_STDIN__'
	}

	return null
}

function getRepoRoot({ adminRoot }) {
	return path.resolve(adminRoot, '..')
}

function tryReadSupabaseFromFlutterConfigs({ repoRoot }) {
	const candidates = [
		path.resolve(repoRoot, 'tool', 'supabase.env.json'),
		path.resolve(repoRoot, 'assets', 'config', 'supabase.env.json'),
	]

	for (const filePath of candidates) {
		const json = readJsonIfExists(filePath)
		if (!json) continue
		const url = normalizeSupabaseUrl(json.SUPABASE_URL)
		const anon = typeof json.SUPABASE_ANON_KEY === 'string' ? json.SUPABASE_ANON_KEY : null
		if (url && anon) {
			return { source: filePath, url, key: anon }
		}
	}
	return null
}

function getUrlRef(url) {
	try {
		const u = new URL(url)
		return u.host.split('.')[0] || null
	} catch {
		return null
	}
}

async function main() {
	if (hasFlag('--help') || hasFlag('-h')) {
		usage()
		return
	}

	const force = hasFlag('--force')

	const scriptDir = path.dirname(fileURLToPath(import.meta.url))
	const adminRoot = path.resolve(scriptDir, '..')
	const repoRoot = getRepoRoot({ adminRoot })

	const envExamplePath = path.join(adminRoot, '.env.example')
	const envLocalPath = path.join(adminRoot, '.env.local')

	const exampleText = readTextIfExists(envExamplePath)
	if (!exampleText) {
		throw new Error('Missing .env.example in admin_dashboard')
	}

	let envLocalText = readTextIfExists(envLocalPath)
	let created = false
	if (!envLocalText) {
		envLocalText = exampleText
		created = true
	}

	let lines = envLocalText.split(/\r?\n/)
	let envIndex = parseEnvLines(lines)
	const changes = []

	// Fill URL + anon key from existing Flutter config (if present).
	const fromFlutter = tryReadSupabaseFromFlutterConfigs({ repoRoot })
	if (fromFlutter) {
		const setUrl = upsertEnvValue(lines, envIndex, 'NEXT_PUBLIC_SUPABASE_URL', fromFlutter.url, { force })
		if (setUrl.changed) changes.push(`NEXT_PUBLIC_SUPABASE_URL (${setUrl.action})`)
		envIndex = parseEnvLines(lines)

		const anonClass = classifySupabaseKey(fromFlutter.key)
		if (anonClass.ok && anonClass.role === 'anon') {
			const setAnon = upsertEnvValue(lines, envIndex, 'NEXT_PUBLIC_SUPABASE_ANON_KEY', anonClass.value, { force })
			if (setAnon.changed) changes.push(`NEXT_PUBLIC_SUPABASE_ANON_KEY (${setAnon.action}, ${maskToken(anonClass.value)})`)
		} else if (anonClass.ok && anonClass.role === 'service_role') {
			// Security guardrail: never write a service_role key into NEXT_PUBLIC_*.
			// We can still use it as the server-only service role key if none is configured.
			const currentService = envIndex.get('SUPABASE_SERVICE_ROLE_KEY')?.rawValue ?? ''
			if (looksLikePlaceholder(currentService)) {
				const setService = upsertEnvValue(lines, envIndex, 'SUPABASE_SERVICE_ROLE_KEY', anonClass.value, { force })
				if (setService.changed) changes.push(`SUPABASE_SERVICE_ROLE_KEY (${setService.action})`)
			}
			console.warn(
				'[setup:supabase] Warning: SUPABASE_ANON_KEY in your Flutter config looks like a service_role key. It was NOT written to NEXT_PUBLIC_SUPABASE_ANON_KEY. Please set a real anon key for client-side usage.',
			)
		} else {
			console.warn(
				`[setup:supabase] Warning: Could not validate SUPABASE_ANON_KEY from ${fromFlutter.source} as a JWT. Skipping NEXT_PUBLIC_SUPABASE_ANON_KEY write.`,
			)
		}
	} else {
		console.warn(
			'[setup:supabase] Note: Could not find tool/supabase.env.json or assets/config/supabase.env.json with SUPABASE_URL + SUPABASE_ANON_KEY. You may need to set Supabase env vars manually in .env.local.',
		)
	}

	// Optionally set the service role key from user input (clipboard/file/stdin).
	let serviceInput = readServiceRoleFromInput()
	if (serviceInput === '__READ_STDIN__') {
		serviceInput = await readStdin()
	}
	if (serviceInput) {
		const classified = classifySupabaseKey(serviceInput)
		if (!classified.ok) {
			throw new Error(
				`Service role key input is not a valid Supabase JWT (${classified.reason}). Copy the "service_role" key from Supabase Dashboard → Project Settings → API.`,
			)
		}
		if (classified.role !== 'service_role') {
			throw new Error(
				`Provided key is not a service_role key (jwt role=${classified.role ?? 'unknown'}). Copy the "service_role" key (server-only), not the anon key.`,
			)
		}

		// Ref mismatch guard when URL is present.
		const urlNow = normalizeSupabaseUrl(envIndex.get('NEXT_PUBLIC_SUPABASE_URL')?.rawValue)
		const urlRef = urlNow ? getUrlRef(urlNow) : null
		if (urlRef && classified.ref && urlRef !== classified.ref) {
			throw new Error(
				`SUPABASE_SERVICE_ROLE_KEY belongs to a different Supabase project (key ref=${classified.ref}, url ref=${urlRef}). Fix NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY pairing.`,
			)
		}

		const setService = upsertEnvValue(lines, envIndex, 'SUPABASE_SERVICE_ROLE_KEY', classified.value, { force: true })
		if (setService.changed) changes.push(`SUPABASE_SERVICE_ROLE_KEY (${setService.action})`)
	}

	// Normalize trailing empty line(s) and write.
	lines = lines.filter((l, idx, arr) => idx < arr.length - 1 || l !== '')
	const output = ensureTrailingNewline(lines.join('\n'))
	fs.writeFileSync(envLocalPath, output, 'utf8')

	console.log(created ? '[setup:supabase] Created .env.local (from .env.example)' : '[setup:supabase] Updated .env.local')
	if (fromFlutter) console.log(`[setup:supabase] Source: ${fromFlutter.source}`)

	if (changes.length) {
		console.log('[setup:supabase] Applied:')
		for (const c of changes) console.log(` - ${c}`)
	} else {
		console.log('[setup:supabase] No changes needed.')
	}

	// Print a safe status summary.
	const finalIndex = parseEnvLines(output.split(/\r?\n/))
	const finalUrl = normalizeSupabaseUrl(finalIndex.get('NEXT_PUBLIC_SUPABASE_URL')?.rawValue)
	const finalAnon = finalIndex.get('NEXT_PUBLIC_SUPABASE_ANON_KEY')?.rawValue
	const finalService = finalIndex.get('SUPABASE_SERVICE_ROLE_KEY')?.rawValue
	const anonInfo = classifySupabaseKey(finalAnon)
	const serviceInfo = classifySupabaseKey(finalService)

	console.log('[setup:supabase] Status:')
	if (finalUrl) {
		try {
			console.log(` - urlHost: ${new URL(finalUrl).host}`)
		} catch {
			console.log(' - urlHost: <invalid url>')
		}
	} else {
		console.log(' - urlHost: <missing>')
	}
	console.log(` - anonKeyRole: ${anonInfo.ok ? anonInfo.role ?? '<unknown>' : '<missing/invalid>'}`)
	console.log(` - serviceRoleConfigured: ${serviceInfo.ok && serviceInfo.role === 'service_role' ? 'yes' : 'no'}`)

	console.log('[setup:supabase] Next steps:')
	console.log(' - Restart the admin dev server: npm run admin (repo root)')
	console.log('   - Or: npm --prefix admin_dashboard run dev')
	if (!(serviceInfo.ok && serviceInfo.role === 'service_role')) {
		console.log(' - Set service role key (server-only):')
		console.log('   - Copy the Supabase service_role key to clipboard, then run (repo root):')
		console.log('     npm run admin:setup:supabase -- --service-from-clipboard')
		console.log('   - Or (admin_dashboard):')
		console.log('     npm run setup:supabase -- --service-from-clipboard')
	}
}

main().catch((e) => {
	console.error(`[setup:supabase] ${e instanceof Error ? e.message : String(e)}`)
	process.exit(1)
})
