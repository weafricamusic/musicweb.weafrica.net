import { NextResponse } from 'next/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getSupabaseServerEnvDebug } from '@/lib/supabase/server'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'

export const runtime = 'nodejs'

function getErrorMeta(err: unknown): { code?: string; status?: number; message?: string } {
	if (!err || typeof err !== 'object') return {}
	const e = err as Record<string, unknown>
	return {
		code: typeof e.code === 'string' ? e.code : undefined,
		status: typeof e.status === 'number' ? e.status : undefined,
		message: typeof e.message === 'string' ? e.message : undefined,
	}
}

export async function POST() {
	const decoded = await verifyFirebaseSessionCookie()
	if (!decoded) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	const env = (() => {
		try {
			return getSupabaseServerEnvDebug()
		} catch {
			return null
		}
	})()

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{
				error:
					'SUPABASE_SERVICE_ROLE_KEY is missing/placeholder. Add it (no quotes/newlines) and restart the server.',
				env,
			},
			{ status: 500 },
		)
	}

	// Try the "new" schema first.
	try {
		const { error } = await supabase
			.from('admins')
			.upsert(
				{ email: (decoded.email ?? '').toLowerCase(), role: 'super_admin', status: 'active', uid: decoded.uid },
				{ onConflict: 'email' },
			)
		if (!error) {
			return NextResponse.json({ ok: true, mode: 'admins' })
		}

		const msg = (error.message ?? '').toLowerCase()
		const { code, status } = getErrorMeta(error)
		if (status === 401 || msg.includes('invalid api key') || msg.includes('jwt') || msg.includes('not authorized')) {
			return NextResponse.json(
				{
					error:
						'Invalid Supabase API key. Verify NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY belong to the same project and that the key is copied exactly (no quotes/newlines).',
					env,
					details: { code, status, message: error.message },
				},
				{ status: 500 },
			)
		}

		// If the table doesn't exist, fall through to legacy.
		if (error.code !== 'PGRST205' && !/could not find the table|schema cache/i.test(error.message ?? '')) {
			return NextResponse.json({ error: error.message, env, details: { code, status } }, { status: 500 })
		}
	} catch {
		// ignore and try legacy
	}

	// Legacy schema: app_admins keyed by Firebase uid.
	const { error: legacyError } = await supabase
		.from('app_admins')
		.upsert({ user_id: decoded.uid, role: 'super_admin' }, { onConflict: 'user_id' })

	if (legacyError) {
		const msg = (legacyError.message ?? '').toLowerCase()
		const { status } = getErrorMeta(legacyError)
		if (status === 401 || msg.includes('invalid api key')) {
			return NextResponse.json(
				{
					error:
						'Invalid Supabase API key. Verify NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY belong to the same project and that the key is copied exactly (no quotes/newlines).',
					env,
					details: { status, message: legacyError.message },
				},
				{ status: 500 },
			)
		}

		return NextResponse.json({ error: legacyError.message, env }, { status: 500 })
	}

	return NextResponse.json({ ok: true, mode: 'app_admins' })
}
