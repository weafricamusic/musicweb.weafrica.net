import { NextResponse } from 'next/server'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { getSupabaseServerEnvDebug } from '@/lib/supabase/server'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

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

export async function GET() {
	if (process.env.NODE_ENV === 'production') {
		return NextResponse.json({ error: 'Not found' }, { status: 404 })
	}

	const decoded = await verifyFirebaseSessionCookie()
	if (!decoded) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	const env = (() => {
		try {
			return getSupabaseServerEnvDebug()
		} catch (e) {
			return { error: e instanceof Error ? e.message : 'Failed to read env' }
		}
	})()

	const adminClient = tryCreateSupabaseAdminClient()
	if (!adminClient) {
		return NextResponse.json(
			{
				env,
				canUseServiceRole: false,
				error:
					'SUPABASE_SERVICE_ROLE_KEY missing/placeholder. Add it (no quotes/newlines) and restart the server.',
			},
			{ status: 200 },
		)
	}

	// Lightweight probe that distinguishes: invalid key (401) vs missing table (PGRST205) vs OK.
	const { error: adminsError } = await adminClient.from('admins').select('id').limit(1)
	const adminsMeta = getErrorMeta(adminsError)

	const { error: countriesError } = await adminClient
		.from('countries')
		.select('country_code')
		.limit(1)
	let countriesProbeError = countriesError
	let countriesMeta = getErrorMeta(countriesProbeError)
	if (countriesProbeError && (countriesMeta.code === '42703' || String(countriesMeta.message ?? '').toLowerCase().includes('country_code'))) {
		const { error } = await adminClient.from('countries').select('code').limit(1)
		countriesProbeError = error
		countriesMeta = getErrorMeta(countriesProbeError)
	}

	return NextResponse.json({
		env,
		canUseServiceRole: true,
		probe: {
			admins: adminsError
				? { ok: false, code: adminsMeta.code, status: adminsMeta.status, message: adminsError.message }
				: { ok: true },
			countries: countriesProbeError
				? { ok: false, code: countriesMeta.code, status: countriesMeta.status, message: countriesProbeError.message }
				: { ok: true },
		},
	})
}
