import dotenv from 'dotenv'
import { createClient } from '@supabase/supabase-js'

// Load env
dotenv.config({ path: '.env.local' })

function mustEnv(name) {
	const raw = process.env[name]
	if (!raw) throw new Error(`Missing ${name} in .env.local`)
	const v = String(raw).trim().replace(/^['"]|['"]$/g, '')
	if (!v) throw new Error(`Empty ${name} in .env.local`)
	if (v.includes('...')) throw new Error(`${name} looks truncated (contains "...")`)
	return v
}

const url = mustEnv('NEXT_PUBLIC_SUPABASE_URL')
const serviceKey = mustEnv('SUPABASE_SERVICE_ROLE_KEY')

const supabase = createClient(url, serviceKey, {
	auth: { persistSession: false, autoRefreshToken: false },
})

async function checkTable(name, select) {
	const { data, error } = await supabase.from(name).select(select).limit(1)
	if (error) {
		return { ok: false, error }
	}
	return { ok: true, sample: data }
}

async function checkRpc() {
	const { data, error } = await supabase.rpc('subscription_plan_counts', { p_country_code: null })
	if (error) return { ok: false, error }
	return { ok: true, sample: data }
}

function summarizeError(err) {
	if (!err) return 'unknown error'
	const e = err
	return {
		message: e.message,
		code: e.code,
		details: e.details,
		hint: e.hint,
	}
}

async function main() {
	console.log('Checking subscriptions schema via service-role…')
	console.log(`- url: ${url}`)

	const plans = await checkTable('subscription_plans', 'plan_id,name,price_mwk,billing_interval')
	console.log('\nsubscription_plans:')
	if (!plans.ok) console.log('  ✗', summarizeError(plans.error))
	else console.log('  ✓ ok')

	const subs = await checkTable('user_subscriptions', 'id,user_id,plan_id,status,started_at,ends_at,country_code')
	console.log('\nuser_subscriptions:')
	if (!subs.ok) console.log('  ✗', summarizeError(subs.error))
	else console.log('  ✓ ok')

	const rpc = await checkRpc()
	console.log('\nsubscription_plan_counts RPC:')
	if (!rpc.ok) console.log('  ✗', summarizeError(rpc.error))
	else console.log('  ✓ ok')

	const ok = plans.ok && subs.ok
	process.exit(ok ? 0 : 2)
}

main().catch((e) => {
	console.error('Fatal:', e?.message || e)
	process.exit(1)
})
