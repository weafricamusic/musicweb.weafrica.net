import dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

function base64UrlDecode(input) {
	const normalized = String(input || '').replace(/-/g, '+').replace(/_/g, '/')
	const padLen = (4 - (normalized.length % 4)) % 4
	const padded = normalized + '='.repeat(padLen)
	return Buffer.from(padded, 'base64').toString('utf8')
}

function tryParseJwtPayload(value) {
	const parts = String(value || '').split('.')
	if (parts.length !== 3) return null
	try {
		return JSON.parse(base64UrlDecode(parts[1] || ''))
	} catch {
		return null
	}
}

function keyMeta(value) {
	const compact = String(value || '').trim().replace(/\s+/g, '')
	const payload = tryParseJwtPayload(compact)
	return {
		len: compact.length || 0,
		role: payload && typeof payload.role === 'string' ? payload.role : undefined,
		ref: payload && typeof payload.ref === 'string' ? payload.ref : undefined,
	}
}

function get(name) {
	const raw = process.env[name]
	if (!raw) return null
	const v = String(raw).trim().replace(/^['"]|['"]$/g, '')
	return v.length ? v : null
}

const url = get('NEXT_PUBLIC_SUPABASE_URL')
const anon = get('NEXT_PUBLIC_SUPABASE_ANON_KEY')
const service = get('SUPABASE_SERVICE_ROLE_KEY')

const missing = []
if (!url) missing.push('NEXT_PUBLIC_SUPABASE_URL')
if (!anon) missing.push('NEXT_PUBLIC_SUPABASE_ANON_KEY')
if (!service) missing.push('SUPABASE_SERVICE_ROLE_KEY')

if (missing.length) {
	console.error(`Missing Supabase env vars: ${missing.join(', ')}`)
	console.error('Fix: set them in admin_dashboard/.env.local, then restart the admin dev server.')
	console.error('- Repo root: `npm run admin`')
	console.error('- Or: `npm --prefix admin_dashboard run dev`')
	console.error('Local-dev helper (macOS): `npm run admin:setup:supabase -- --service-from-clipboard`')
	console.error('Where to get them: Supabase Dashboard → Project Settings → API')
	console.error('- URL: Project URL')
	console.error('- anon key: anon public key (safe for client)')
	console.error('- service role key: service_role (server-only; keep secret)')
	process.exit(1)
}

try {
	const u = new URL(url)
	if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new Error('URL must be http(s)')
} catch (e) {
	console.error(`NEXT_PUBLIC_SUPABASE_URL is not a valid URL: ${e?.message || e}`)
	process.exit(1)
}

console.log('Supabase env looks present:')
console.log(`- NEXT_PUBLIC_SUPABASE_URL: ${url}`)
{
	const anonMeta = keyMeta(anon)
	const svcMeta = keyMeta(service)
	console.log(
		`- NEXT_PUBLIC_SUPABASE_ANON_KEY: <set> (len=${anonMeta.len}${anonMeta.role ? `, role=${anonMeta.role}` : ''}${anonMeta.ref ? `, ref=${anonMeta.ref}` : ''})`,
	)
	console.log(
		`- SUPABASE_SERVICE_ROLE_KEY: <set> (len=${svcMeta.len}${svcMeta.role ? `, role=${svcMeta.role}` : ''}${svcMeta.ref ? `, ref=${svcMeta.ref}` : ''})`,
	)
}
