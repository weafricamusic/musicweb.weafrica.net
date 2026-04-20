import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'

dotenv.config({ path: '.env.local' })

function normalizeEnv(name: string): string {
	const raw = process.env[name]
	if (!raw) {
		throw new Error(`Missing ${name} in .env.local`)
	}
	return raw.trim().replace(/^['"]|['"]$/g, '')
}

function looksLikeJwt(value: string): boolean {
	return value.split('.').length === 3
}

function looksLikeSupabaseSecretKey(value: string): boolean {
	return value.startsWith('sb_secret_')
}

const supabaseUrl = normalizeEnv('NEXT_PUBLIC_SUPABASE_URL')
const serviceRoleKey = normalizeEnv('SUPABASE_SERVICE_ROLE_KEY')

if (!(looksLikeJwt(serviceRoleKey) || looksLikeSupabaseSecretKey(serviceRoleKey))) {
	throw new Error(
		'SUPABASE_SERVICE_ROLE_KEY must be either a JWT or a Supabase secret key (sb_secret_...). Re-copy it from Supabase Settings → API.',
	)
}

const identifier = process.argv[2]
const role = (process.argv[3] ?? 'admin') as 'admin' | 'super_admin'

if (!identifier) {
	console.error('Usage: npx ts-node supabase/seed-admin.ts <user_id|email> [admin|super_admin]')
	process.exit(1)
}

if (role !== 'admin' && role !== 'super_admin') {
	console.error('Role must be admin or super_admin')
	process.exit(1)
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
	auth: { persistSession: false, autoRefreshToken: false },
})

async function main() {
	let userId: string | undefined
	if (identifier.includes('@')) {
		const email = identifier.toLowerCase()
		for (let page = 1; page <= 50; page++) {
			const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 200 })
			if (error) throw error
			const match = data.users.find((u) => (u.email ?? '').toLowerCase() === email)
			if (match) {
				userId = match.id
				break
			}
			if (data.users.length < 200) break
		}
		if (!userId) {
			throw new Error(
				`No auth user found for email=${identifier}. Create the user first (sign up / invite), then re-run.`,
			)
		}
	} else {
		userId = identifier
		const { data: userData, error: userError } = await supabase.auth.admin.getUserById(userId)
		if (userError) throw userError
		if (!userData.user) {
			throw new Error(
				`No auth user found for user_id=${userId}. Create the user first (sign up / invite), then re-run.`,
			)
		}
	}

	const { error: upsertError } = await supabase
		.from('admin_roles')
		.upsert({ user_id: userId, role }, { onConflict: 'user_id' })

	if (upsertError) throw upsertError

	console.log(`Seeded admin role: user_id=${userId} role=${role}`)
}

main().catch((err) => {
	console.error('Error:', err)
	process.exit(1)
})
