import dotenv from 'dotenv'
import { createClient } from '@supabase/supabase-js'

dotenv.config({ path: '.env.local' })

function get(name) {
	const raw = process.env[name]
	if (!raw) return null
	const v = String(raw).trim().replace(/^['"]|['"]$/g, '')
	return v.length ? v : null
}

const url = get('NEXT_PUBLIC_SUPABASE_URL')
const anon = get('NEXT_PUBLIC_SUPABASE_ANON_KEY')
const service = get('SUPABASE_SERVICE_ROLE_KEY')

if (!url) {
	console.error('Missing NEXT_PUBLIC_SUPABASE_URL in .env.local')
	process.exit(1)
}
if (!anon && !service) {
	console.error('Missing NEXT_PUBLIC_SUPABASE_ANON_KEY (or SUPABASE_SERVICE_ROLE_KEY) in .env.local')
	process.exit(1)
}

const useService = String(process.env.USE_SERVICE_ROLE || '').trim() === '1'
const key = useService ? service : anon
if (!key) {
	console.error(useService ? 'USE_SERVICE_ROLE=1 but SUPABASE_SERVICE_ROLE_KEY is missing' : 'anon key is missing')
	process.exit(1)
}

const supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

const candidates = ['dj_wallets', 'dj_wallet', 'wallets']

async function probe(name) {
	// 1) Existence probe (select id only)
	const r1 = await supabase.from(name).select('id', { count: 'exact' }).limit(1)
	// 2) Column probe (common wallet columns)
	const r2 = await supabase.from(name).select('id,dj_id,user_id,coins,locked_coins,created_at,updated_at', { count: 'exact' }).limit(1)

	return { r1, r2 }
}

console.log(`Probing wallet storage on ${new URL(url).host}`)
console.log(`Key mode: ${useService ? 'service_role' : 'anon'}`)

for (const name of candidates) {
	try {
		const { r1, r2 } = await probe(name)

		const e1 = r1.error
		const e2 = r2.error

		console.log(`\n== ${name} ==`)
		if (e1) {
			console.log(`existence: ERROR code=${e1.code || 'n/a'} msg=${e1.message}`)
		} else {
			console.log(`existence: OK (count=${r1.count ?? 'n/a'})`) // count can be null depending on config
		}

		if (e2) {
			console.log(`columns:   ERROR code=${e2.code || 'n/a'} msg=${e2.message}`)
		} else {
			console.log('columns:   OK')
		}
	} catch (err) {
		console.log(`\n== ${name} ==`)
		console.log(`unexpected error: ${err instanceof Error ? err.message : String(err)}`)
	}
}

console.log('\nTip: run with USE_SERVICE_ROLE=1 to probe as service_role.')
