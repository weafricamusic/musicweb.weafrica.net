import { NextResponse } from 'next/server'

import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function getSecret(req: Request): string {
	return (
		req.headers.get('x-weafrica-callback-secret') ||
		req.headers.get('X-WeAfrica-Callback-Secret') ||
		''
	)
		.trim()
}

export async function POST(req: Request) {
	const expected = String(process.env.PIPEDREAM_CALLBACK_SECRET ?? '').trim()
	if (!expected) {
		return json({ error: 'Server not configured (missing PIPEDREAM_CALLBACK_SECRET)' }, { status: 500 })
	}

	const provided = getSecret(req)
	if (!provided || provided !== expected) {
		return json({ error: 'Unauthorized' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as any
	if (!body || typeof body !== 'object') return json({ error: 'Invalid JSON body' }, { status: 400 })

	const generationId = String(body.generation_id ?? body.id ?? '').trim() || null
	const providerJobId = String(body.provider_job_id ?? body.job_id ?? '').trim() || null
	const status = String(body.status ?? '').trim().toLowerCase()

	const nextStatus = status === 'running' || status === 'succeeded' || status === 'failed' ? status : null
	if (!generationId && !providerJobId) return json({ error: 'Missing generation_id or provider_job_id' }, { status: 400 })
	if (!nextStatus) return json({ error: 'Missing/invalid status (running|succeeded|failed)' }, { status: 400 })

	const patch: Record<string, unknown> = {
		status: nextStatus,
		provider_job_id: providerJobId ?? undefined,
		result_audio_url: body.audio_url ? String(body.audio_url) : undefined,
		result_track_id: body.track_id ? String(body.track_id) : undefined,
		error: body.error ? String(body.error) : null,
		meta: body.meta && typeof body.meta === 'object' ? body.meta : body,
		completed_at: nextStatus === 'succeeded' || nextStatus === 'failed' ? new Date().toISOString() : null,
	}

	let q = supabase.from('ai_generations').update(patch)
	if (generationId) q = q.eq('id', generationId)
	else q = q.eq('provider_job_id', providerJobId)

	const { data, error } = await q.select('id,status,result_audio_url,result_track_id,provider_job_id').maybeSingle()
	if (error) return json({ error: error.message }, { status: 500 })
	if (!data) return json({ error: 'Not found' }, { status: 404 })

	return json({ ok: true, generation: data })
}
