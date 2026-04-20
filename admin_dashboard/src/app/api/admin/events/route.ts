import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { assertPermission, getAdminContext } from '@/lib/admin/session'
import { logAdminAction } from '@/lib/admin/audit'
import { NextResponse } from 'next/server'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const url = new URL(req.url)
	const q = url.searchParams.get('q')?.trim() ?? ''
	const status = url.searchParams.get('status')?.trim() ?? ''
	const limitRaw = url.searchParams.get('limit')
	const limit = Math.max(1, Math.min(200, Number(limitRaw ?? 100) || 100))

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	let query = supabase
		.from('ticketing_events')
		.select(
			'id,title,description,cover_image_url,venue_name,venue_address,city,country_code,starts_at,ends_at,timezone,status,created_by_admin_email,created_at,updated_at',
		)

	if (status) query = query.eq('status', status)
	if (q) query = query.ilike('title', `%${q.replace(/%/g, '')}%`)

	const { data, error } = await query.order('starts_at', { ascending: false }).limit(limit)
	if (error) return json({ ok: false, error: String(error.message ?? 'Query failed') }, { status: 500 })

	return json({ ok: true, data: data ?? [] })
}

type CreateBody = {
	title: string
	description?: string | null
	cover_image_url?: string
	venue_name?: string | null
	venue_address?: string | null
	city?: string | null
	country_code?: string | null
	starts_at: string
	ends_at?: string | null
	timezone?: string
	status?: 'draft' | 'published' | 'cancelled'
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as CreateBody | null
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid body' }, { status: 400 })

	const title = String(body.title ?? '').trim()
	if (!title) return json({ ok: false, error: 'title is required' }, { status: 400 })

	const startsAt = String(body.starts_at ?? '').trim()
	if (!startsAt) return json({ ok: false, error: 'starts_at is required' }, { status: 400 })
	const starts = new Date(startsAt)
	if (Number.isNaN(starts.getTime())) return json({ ok: false, error: 'starts_at must be ISO date' }, { status: 400 })

	const endsAt = body.ends_at == null ? null : String(body.ends_at).trim()
	if (endsAt) {
		const ends = new Date(endsAt)
		if (Number.isNaN(ends.getTime())) return json({ ok: false, error: 'ends_at must be ISO date' }, { status: 400 })
		if (ends.getTime() < starts.getTime()) return json({ ok: false, error: 'ends_at must be >= starts_at' }, { status: 400 })
	}

	const status = (body.status ?? 'draft') as string
	if (status !== 'draft' && status !== 'published' && status !== 'cancelled') {
		return json({ ok: false, error: 'Invalid status' }, { status: 400 })
	}

	const payload = {
		title,
		description: body.description ?? null,
		cover_image_url: String(body.cover_image_url ?? ''),
		venue_name: body.venue_name ?? null,
		venue_address: body.venue_address ?? null,
		city: body.city ?? null,
		country_code: body.country_code ? String(body.country_code).trim().toUpperCase() : null,
		starts_at: starts.toISOString(),
		ends_at: endsAt ? new Date(endsAt).toISOString() : null,
		timezone: String(body.timezone ?? 'UTC') || 'UTC',
		status,
		created_by_admin_email: ctx.admin.email,
	}

	const { data: created, error } = await supabase
		.from('ticketing_events')
		.insert(payload)
		.select(
			'id,title,description,cover_image_url,venue_name,venue_address,city,country_code,starts_at,ends_at,timezone,status,created_by_admin_email,created_at,updated_at',
		)
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Insert failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'events.create',
		target_type: 'event',
		target_id: String((created as any)?.id ?? ''),
		before_state: null,
		after_state: created as any,
		meta: { module: 'events' },
		req,
	})

	return json({ ok: true, data: created })
}
