import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

function usage() {
	console.log(
		[
			'Usage:',
			'  npm --prefix admin_dashboard run setup:firebase-admin -- --from /absolute/or/relative/path/to/key.json',
			'  npm --prefix admin_dashboard run setup:firebase-admin -- --from-stdin   # pipe JSON to stdin',
			'  npm --prefix admin_dashboard run setup:firebase-admin -- --from-clipboard # macOS pbpaste',
			'',
			'Notes:',
			'- This creates admin_dashboard/firebase-service-account.json (gitignored).',
			'- It never prints the private key.',
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

function ensureParentDir(filePath) {
	fs.mkdirSync(path.dirname(filePath), { recursive: true })
}

function chmod600(filePath) {
	if (process.platform === 'win32') return
	try {
		fs.chmodSync(filePath, 0o600)
	} catch {
		// best-effort only
	}
}

function parseAndValidateServiceAccount(rawJsonText) {
	let parsed
	try {
		parsed = JSON.parse(rawJsonText)
	} catch {
		throw new Error('Service account input is not valid JSON')
	}

	if (!parsed || typeof parsed !== 'object') {
		throw new Error('Service account JSON must be an object')
	}

	const projectId = typeof parsed.project_id === 'string' ? parsed.project_id.trim() : ''
	const clientEmail = typeof parsed.client_email === 'string' ? parsed.client_email.trim() : ''
	const privateKey = typeof parsed.private_key === 'string' ? parsed.private_key.trim() : ''

	if (!projectId) throw new Error('Service account JSON missing project_id')
	if (!clientEmail) throw new Error('Service account JSON missing client_email')
	if (!privateKey) throw new Error('Service account JSON missing private_key')
	if (!privateKey.includes('BEGIN PRIVATE KEY') || !privateKey.includes('END PRIVATE KEY')) {
		throw new Error('Service account JSON private_key does not look like a PEM key')
	}

	return {
		projectId,
		clientEmail,
		privateKeyId: typeof parsed.private_key_id === 'string' ? parsed.private_key_id.trim() : '',
		parsed,
	}
}

async function readStdin() {
	const chunks = []
	for await (const chunk of process.stdin) chunks.push(chunk)
	return Buffer.concat(chunks).toString('utf8')
}

async function main() {
	const destPath = path.resolve(process.cwd(), 'firebase-service-account.json')

	if (hasFlag('--help') || hasFlag('-h')) {
		usage()
		return
	}

	if (fs.existsSync(destPath)) {
		console.log(`[setup:firebase-admin] OK: ${destPath} already exists.`)
		return
	}

	let raw = null

	const fromPath = getArgValue('--from')
	if (fromPath) {
		const resolved = path.isAbsolute(fromPath) ? fromPath : path.resolve(process.cwd(), fromPath)
		if (!fs.existsSync(resolved)) {
			throw new Error(`File not found: ${resolved}`)
		}
		raw = fs.readFileSync(resolved, 'utf8')
	} else if (hasFlag('--from-stdin')) {
		raw = await readStdin()
	} else if (hasFlag('--from-clipboard')) {
		if (process.platform !== 'darwin') {
			throw new Error('--from-clipboard is only supported on macOS (uses pbpaste)')
		}
		raw = execFileSync('pbpaste', { encoding: 'utf8' })
	} else {
		console.error('[setup:firebase-admin] Missing input.')
		usage()
		process.exitCode = 1
		return
	}

	if (!raw || !String(raw).trim()) {
		throw new Error('No input received (empty).')
	}

	const { projectId, clientEmail, privateKeyId, parsed } = parseAndValidateServiceAccount(String(raw))

	ensureParentDir(destPath)
	fs.writeFileSync(destPath, JSON.stringify(parsed, null, 2) + '\n', 'utf8')
	chmod600(destPath)

	console.log('[setup:firebase-admin] Wrote firebase service account credential file:')
	console.log(`- path: ${destPath}`)
	console.log(`- project_id: ${projectId}`)
	console.log(`- client_email: ${clientEmail}`)
	if (privateKeyId) console.log(`- private_key_id: ${privateKeyId}`)
	console.log('')
	console.log('[setup:firebase-admin] Next:')
	console.log('- Verify credentials: npm --prefix admin_dashboard run check:firebase-admin:token')
	console.log('- Restart dev server: npm run admin')
}

main().catch((e) => {
	console.error(`[setup:firebase-admin] ${e instanceof Error ? e.message : String(e)}`)
	process.exit(1)
})
