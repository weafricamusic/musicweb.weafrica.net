export const runtime = 'nodejs'

import { NextResponse } from 'next/server'

import { assertPermission, getAdminContext } from '@/lib/admin/session'
import { logAdminAction } from '@/lib/admin/audit'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function isSchemaMissingError(message: string | undefined): boolean {
	const msg = String(message ?? '')
	return /schema cache|could not find the table|does not exist|PGRST205/i.test(msg)
}

type Filter = 'pending' | 'live' | 'taken_down' | 'all'

function normalizeFilter(value: unknown): Filter {
	const v = String(value ?? '').trim().toLowerCase()
	if (v === 'pending' || v === 'live' || v === 'taken_down' || v === 'all') return v
	if (v === 'taken-down' || v === 'removed') return 'taken_down'
	return 'pending'
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const url = new URL(req.url)
	const filter = normalizeFilter(url.searchParams.get('filter'))

	let q = supabase
		.from('videos')
		.select('*')
		.order('created_at', { ascending: false })
		.limit(200)

	if (filter === 'pending') q = q.eq('approved', false)
	if (filter === 'live') q = q.eq('approved', true).eq('is_active', true)
	if (filter === 'taken_down') q = q.eq('is_active', false)

	const { data, error } = await q
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "videos table not found. Apply migrations and then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	return json({ ok: true, videos: data ?? [], filter })
}

type PatchBody =
	| { action: 'approve'; id: string; reason?: string }
	| { action: 'take_down'; id: string; reason?: string }
	| { action: 'restore'; id: string; reason?: string }

export async function PATCH(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })
	const id = String((body as any).id ?? '').trim()
	if (!id) return json({ error: 'Missing id' }, { status: 400 })
	const reason = String((body as any).reason ?? '').trim()

	const { data: beforeState, error: beforeError } = await supabase.from('videos').select('*').eq('id', id).single()
	if (beforeError) {
		if (isSchemaMissingError(beforeError.message)) {
			return json(
				{ error: "videos table not found. Apply migrations and then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: beforeError.message }, { status: 500 })
	}

	let patch: Record<string, unknown> | null = null
	if (body.action === 'approve') patch = { approved: true }
	if (body.action === 'take_down') patch = { is_active: false }
	if (body.action === 'restore') patch = { is_active: true }
	if (!patch) return json({ error: 'Invalid action' }, { status: 400 })

	const { data, error } = await supabase.from('videos').update(patch).eq('id', id).select('*').single()
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "videos table not found. Apply migrations and then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	logAdminAction({
		ctx,
		action: `videos.${body.action}`,
		target_type: 'video',
		target_id: id,
		before_state: (beforeState ?? null) as any,
		after_state: (data ?? null) as any,
		meta: reason ? { reason } : {},
		req,
	}).catch(() => null)

	return json({ ok: true, video: data })
}
