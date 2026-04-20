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
		.replace(/\\r/g, '')
		.replace(/\\n/g, '')
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

async function probeSubscriptionsByPlanCode(supabase, planCode) {
	// Some deployments may not have plan_code/plan_name yet; try best-effort.
	let res = await supabase
		.from('subscriptions')
		.select('id,name,plan_code,plan_name')
		.eq('plan_code', planCode)
		.limit(1)
		.maybeSingle()
	if (res.error && String(res.error.message ?? '').includes('does not exist')) {
		return { subPlanCode: planCode, ok: false, missing: true, error: { message: res.error.message, code: res.error.code } }
	}
	if (res.error && String(res.error.message ?? '').toLowerCase().includes('column subscriptions.plan_code does not exist')) {
		// Fall back to lookup by name.
		res = await supabase
			.from('subscriptions')
			.select('id,name')
			.ilike('name', planCode)
			.limit(1)
			.maybeSingle()
		if (res.error) {
			return { subPlanCode: planCode, ok: false, error: { message: res.error.message, code: res.error.code } }
		}
		return { subPlanCode: planCode, ok: true, exists: Boolean(res.data), row: res.data ?? null, mode: 'name' }
	}
	if (res.error) {
		return { subPlanCode: planCode, ok: false, error: { message: res.error.message, code: res.error.code } }
	}
	return { subPlanCode: planCode, ok: true, exists: Boolean(res.data), row: res.data ?? null, mode: 'plan_code' }
}

async function probeRpc(supabase, fn, args = {}) {
	const res = await supabase.rpc(fn, args)
	if (res.error) {
		return {
			fn,
			ok: false,
			error: { message: res.error.message, code: res.error.code, details: res.error.details, hint: res.error.hint },
		}
	}
	return { fn, ok: true, rows: Array.isArray(res.data) ? res.data.length : 0 }
}

async function probePlanRow(supabase, planId) {
	const res = await supabase
		.from('subscription_plans')
		.select('plan_id,name,price_mwk,billing_interval')
		.eq('plan_id', planId)
		.limit(1)
		.maybeSingle()
	if (res.error) {
		return {
			planId,
			ok: false,
			error: { message: res.error.message, code: res.error.code, details: res.error.details, hint: res.error.hint },
		}
	}
	return { planId, ok: true, exists: Boolean(res.data), row: res.data ?? null }
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

	console.log('Checking subscriptions tables/RPC...')

	const checks = []
	checks.push(await probeTable(supabase, 'subscription_plans', 'plan_id,name,price_mwk,billing_interval'))
	checks.push(await probeTable(supabase, 'user_subscriptions', 'id,user_id,plan_id,status,created_at'))
	checks.push(await probeTable(supabase, 'subscriptions', 'id,name'))
	checks.push(await probeRpc(supabase, 'subscription_plan_counts', { p_country_code: null }))
	checks.push(await probePlanRow(supabase, 'starter'))
	checks.push(await probePlanRow(supabase, 'pro'))
	checks.push(await probePlanRow(supabase, 'elite'))
	checks.push(await probeSubscriptionsByPlanCode(supabase, 'starter'))
	checks.push(await probeSubscriptionsByPlanCode(supabase, 'pro'))
	checks.push(await probeSubscriptionsByPlanCode(supabase, 'elite'))
	checks.push(await probePlanRow(supabase, 'free'))
	checks.push(await probePlanRow(supabase, 'premium'))
	checks.push(await probePlanRow(supabase, 'platinum'))

	for (const c of checks) {
		if (c.table) {
			if (c.ok) console.log(`✓ table ${c.table}: OK (rows sampled=${c.rows})`)
			else if (c.missing) console.log(`✗ table ${c.table}: MISSING (apply migrations)`)
			else console.log(`✗ table ${c.table}: ERROR: ${c.error?.message ?? 'unknown'}`)
		} else if (c.planId) {
			if (!c.ok) console.log(`✗ plan ${c.planId}: ERROR: ${c.error?.message ?? 'unknown'}`)
			else if (!c.exists) console.log(`✗ plan ${c.planId}: MISSING (seed subscription_plans)`)
			else console.log(`✓ plan ${c.planId}: OK (${c.row?.name ?? 'row present'})`)
		} else if (c.subPlanCode) {
			if (!c.ok && c.missing) console.log(`✗ subscriptions(${c.subPlanCode}): MISSING table/column (apply subscriptions alignment/compat migrations)`)
			else if (!c.ok) console.log(`✗ subscriptions(${c.subPlanCode}): ERROR: ${c.error?.message ?? 'unknown'}`)
			else if (!c.exists) console.log(`✗ subscriptions(${c.subPlanCode}): MISSING row (seed public.subscriptions)`)
			else console.log(`✓ subscriptions(${c.subPlanCode}): OK (${c.row?.name ?? 'row present'})`)
		} else {
			if (c.ok) console.log(`✓ rpc ${c.fn}: OK (rows returned=${c.rows})`)
			else console.log(`✗ rpc ${c.fn}: ERROR: ${c.error?.message ?? 'unknown'}`)
		}
	}

	const missing = checks.filter((c) => c.table && !c.ok && c.missing)
	if (missing.length) {
		console.log('\nNext step: apply DB migrations to your Supabase project (recommended):')
		console.log('  supabase db push --include-all')
		console.log('or run the subscriptions migration in the Supabase SQL editor:')
		console.log('  supabase/migrations/20260114120000_subscriptions_core.sql')
		process.exit(2)
	}
}

main().catch((err) => {
	console.error(err)
	process.exit(1)
})
