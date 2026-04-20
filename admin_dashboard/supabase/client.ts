import { createClient } from '@supabase/supabase-js'

function requiredEnv(name: string): string {
	const value = process.env[name]
	if (!value) {
		throw new Error(`Missing required env var: ${name}`)
	}
	return value
}

export const supabase = createClient(
	requiredEnv('NEXT_PUBLIC_SUPABASE_URL'),
	requiredEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY'),
)


