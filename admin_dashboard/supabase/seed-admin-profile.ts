import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

type AdminRole = 'super_admin' | 'operations_admin' | 'finance_admin' | 'support_admin'

function normalizeEnv(name: string): string {
	const raw = process.env[name]
	if (!raw) throw new Error(`Missing ${name} in .env.local`)
	return raw.trim().replace(/^['"]|['"]$/g, '')
}

const identifier = process.argv[2]
const role = (process.argv[3] ?? 'super_admin') as AdminRole

if (!identifier) {
	console.error(
		'Usage: npx ts-node supabase/seed-admin-profile.ts <email|firebase_uid> [super_admin|operations_admin|finance_admin|support_admin]',
	)
	process.exit(1)
}

if (!['super_admin', 'operations_admin', 'finance_admin', 'support_admin'].includes(role)) {
	console.error('Invalid role. Expected one of: super_admin, operations_admin, finance_admin, support_admin')
	process.exit(1)
}

const supabaseUrl = normalizeEnv('NEXT_PUBLIC_SUPABASE_URL')
const serviceRoleKey = normalizeEnv('SUPABASE_SERVICE_ROLE_KEY')

const supabase = createClient(supabaseUrl, serviceRoleKey, {
	auth: { persistSession: false, autoRefreshToken: false },
})

async function main() {
	const isEmail = identifier.includes('@')

	// Try the "new" schema first.
	if (isEmail) {
		const email = identifier.toLowerCase()
		const { error } = await supabase
			.from('admins')
			.upsert({ email, role, status: 'active' }, { onConflict: 'email' })
		if (!error) {
			console.log(`Seeded admin profile: table=admins email=${email} role=${role} status=active`)
			return
		}
		if (error.code !== 'PGRST205') throw error
		console.error(
			'public.admins does not exist in this Supabase project. For the legacy schema, re-run with the Firebase UID instead of email.',
		)
		process.exit(1)
	}

	// Legacy schema: app_admins keyed by Firebase uid (text).
	const uid = identifier
	const { error: legacyError } = await supabase
		.from('app_admins')
		.upsert({ user_id: uid, role }, { onConflict: 'user_id' })

	if (legacyError) throw legacyError
	console.log(`Seeded admin profile: table=app_admins user_id=${uid} role=${role}`)
}

main().catch((err) => {
	console.error('Error:', err)
	process.exit(1)
})
