import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { assertPermission, getAdminContext } from '@/lib/admin/session'
import { logAdminAction } from '@/lib/admin/audit'
import { NextResponse } from 'next/server'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(_: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const { id } = await params
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data, error } = await supabase
		.from('ticketing_events')
		.select(
			'id,title,description,cover_image_url,venue_name,venue_address,city,country_code,starts_at,ends_at,timezone,status,created_by_admin_email,created_at,updated_at',
		)
		.eq('id', id)
		.maybeSingle()

	if (error) return json({ ok: false, error: String(error.message ?? 'Query failed') }, { status: 500 })
	if (!data) return json({ ok: false, error: 'Not found' }, { status: 404 })

	return json({ ok: true, data })
}

type PatchBody = {
	title?: string
	description?: string | null
	cover_image_url?: string
	venue_name?: string | null
	venue_address?: string | null
	city?: string | null
	country_code?: string | null
	starts_at?: string
	ends_at?: string | null
	timezone?: string
	status?: 'draft' | 'published' | 'cancelled'
}

export async function PATCH(req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const { id } = await params
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid body' }, { status: 400 })

	const { data: before, error: beforeErr } = await supabase
		.from('ticketing_events')
		.select('id,title,description,cover_image_url,venue_name,venue_address,city,country_code,starts_at,ends_at,timezone,status')
		.eq('id', id)
		.maybeSingle()
	if (beforeErr) return json({ ok: false, error: String(beforeErr.message ?? 'Query failed') }, { status: 500 })
	if (!before) return json({ ok: false, error: 'Not found' }, { status: 404 })

	const patch: Record<string, unknown> = {}
	if (body.title != null) {
		const v = String(body.title).trim()
		if (!v) return json({ ok: false, error: 'title cannot be empty' }, { status: 400 })
		patch.title = v
	}
	if ('description' in body) patch.description = body.description ?? null
	if (body.cover_image_url != null) patch.cover_image_url = String(body.cover_image_url)
	if ('venue_name' in body) patch.venue_name = body.venue_name ?? null
	if ('venue_address' in body) patch.venue_address = body.venue_address ?? null
	if ('city' in body) patch.city = body.city ?? null
	if ('country_code' in body) patch.country_code = body.country_code ? String(body.country_code).trim().toUpperCase() : null
	if (body.timezone != null) patch.timezone = String(body.timezone || 'UTC')
	if (body.status != null) {
		const s = String(body.status)
		if (s !== 'draft' && s !== 'published' && s !== 'cancelled') {
			return json({ ok: false, error: 'Invalid status' }, { status: 400 })
		}
		patch.status = s
	}
	if (body.starts_at != null) {
		const d = new Date(String(body.starts_at))
		if (Number.isNaN(d.getTime())) return json({ ok: false, error: 'starts_at must be ISO date' }, { status: 400 })
		patch.starts_at = d.toISOString()
	}
	if ('ends_at' in body) {
		if (body.ends_at == null) {
			patch.ends_at = null
		} else {
			const d = new Date(String(body.ends_at))
			if (Number.isNaN(d.getTime())) return json({ ok: false, error: 'ends_at must be ISO date' }, { status: 400 })
			patch.ends_at = d.toISOString()
		}
	}

	if (!Object.keys(patch).length) return json({ ok: false, error: 'No changes' }, { status: 400 })

	const { data: updated, error } = await supabase
		.from('ticketing_events')
		.update(patch)
		.eq('id', id)
		.select(
			'id,title,description,cover_image_url,venue_name,venue_address,city,country_code,starts_at,ends_at,timezone,status,created_by_admin_email,created_at,updated_at',
		)
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Update failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'events.update',
		target_type: 'event',
		target_id: id,
		before_state: before as any,
		after_state: updated as any,
		meta: { module: 'events' },
		req,
	})

	return json({ ok: true, data: updated })
}

export async function DELETE(req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const { id } = await params
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data: before, error: beforeErr } = await supabase
		.from('ticketing_events')
		.select('id,title,status,starts_at')
		.eq('id', id)
		.maybeSingle()
	if (beforeErr) return json({ ok: false, error: String(beforeErr.message ?? 'Query failed') }, { status: 500 })
	if (!before) return json({ ok: false, error: 'Not found' }, { status: 404 })

	const { error } = await supabase.from('ticketing_events').delete().eq('id', id)
	if (error) return json({ ok: false, error: String(error.message ?? 'Delete failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'events.delete',
		target_type: 'event',
		target_id: id,
		before_state: before as any,
		after_state: null,
		meta: { module: 'events' },
		req,
	})

	return json({ ok: true })
}
