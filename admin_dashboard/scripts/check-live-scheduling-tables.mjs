import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'

// Loads local env for scripts
dotenv.config({ path: '.env.local' })

function getEnv(name) {
	const raw = process.env[name]
	if (!raw) return null
	const trimmed = String(raw)
		.trim()
		.replace(/^['"]|['"]$/g, '')
		.replace(/\r/g, '')
		.replace(/\n/g, '')
	return trimmed.length ? trimmed : null
}

function isMissingTableError(err) {
	const msg = String(err?.message ?? '')
	const code = String(err?.code ?? '')
	return code === '42P01' || code === 'PGRST205' || /schema cache|could not find|does not exist/i.test(msg)
}

async function probeTable(supabase, table, select = '*') {
	const res = await supabase.from(table).select(select).limit(1)
	if (res.error) {
		return {
			table,
			ok: false,
			missing: isMissingTableError(res.error),
			error: { message: res.error.message, code: res.error.code, details: res.error.details, hint: res.error.hint },
		}
	}
	return { table, ok: true, missing: false, rows: Array.isArray(res.data) ? res.data.length : 0 }
}

async function main() {
	const url = getEnv('NEXT_PUBLIC_SUPABASE_URL') ?? getEnv('SUPABASE_URL')
	const serviceKey = getEnv('SUPABASE_SERVICE_ROLE_KEY')
	if (!url || !serviceKey) {
		console.error('Missing env vars. Need NEXT_PUBLIC_SUPABASE_URL (or SUPABASE_URL) and SUPABASE_SERVICE_ROLE_KEY in .env.local')
		if (!url) console.error('- missing: NEXT_PUBLIC_SUPABASE_URL (or SUPABASE_URL)')
		if (!serviceKey) console.error('- missing/empty: SUPABASE_SERVICE_ROLE_KEY')
		process.exit(1)
	}

	const supabase = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })

	console.log('Checking live scheduling/control tables...')

	const checks = []
	// Control plane (already used by admin UI)
	checks.push(await probeTable(supabase, 'live_streams', 'id,channel_name,status,started_at,region'))
	// Scheduling plane (required for live scheduling feature)
	checks.push(
		await probeTable(
			supabase,
			'live_sessions',
			'id,channel_name,host_type,host_id,stream_type,status,scheduled_start_at,started_at,region,created_at'
		)
	)

	for (const c of checks) {
		if (c.ok) console.log(`✓ table ${c.table}: OK (rows sampled=${c.rows})`)
		else if (c.missing) console.log(`✗ table ${c.table}: MISSING (apply migrations)`)
		else console.log(`✗ table ${c.table}: ERROR: ${c.error?.message ?? 'unknown'}`)
	}

	const missing = checks.filter((c) => !c.ok && c.missing)
	if (missing.length) {
		console.log('\nNext step: apply DB migrations to your Supabase project:')
		console.log('  supabase db push --include-all')
		console.log('\nRelevant migration for scheduling:')
		console.log('  supabase/migrations/20260216183000_live_sessions.sql')
		process.exit(2)
	}
}

main().catch((err) => {
	console.error(err)
	process.exit(1)
})
