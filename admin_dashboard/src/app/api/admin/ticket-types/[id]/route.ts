import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { assertPermission, getAdminContext } from '@/lib/admin/session'
import { logAdminAction } from '@/lib/admin/audit'
import { NextResponse } from 'next/server'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

type PatchBody = {
	name?: string
	description?: string | null
	price_cents?: number
	currency_code?: string
	quantity_total?: number
	sales_start_at?: string | null
	sales_end_at?: string | null
	is_active?: boolean
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
		.from('ticketing_ticket_types')
		.select('id,event_id,name,description,price_cents,currency_code,quantity_total,quantity_sold,sales_start_at,sales_end_at,is_active')
		.eq('id', id)
		.maybeSingle()
	if (beforeErr) return json({ ok: false, error: String(beforeErr.message ?? 'Query failed') }, { status: 500 })
	if (!before) return json({ ok: false, error: 'Not found' }, { status: 404 })

	const patch: Record<string, unknown> = {}
	if (body.name != null) {
		const v = String(body.name).trim()
		if (!v) return json({ ok: false, error: 'name cannot be empty' }, { status: 400 })
		patch.name = v
	}
	if ('description' in body) patch.description = body.description ?? null
	if (body.price_cents != null) {
		const price = Number(body.price_cents)
		if (!Number.isFinite(price) || price < 0) return json({ ok: false, error: 'Invalid price_cents' }, { status: 400 })
		patch.price_cents = Math.trunc(price)
	}
	if (body.currency_code != null) {
		const currency = String(body.currency_code).trim().toUpperCase()
		if (!/^[A-Z]{3}$/.test(currency)) return json({ ok: false, error: 'Invalid currency_code' }, { status: 400 })
		patch.currency_code = currency
	}
	if (body.quantity_total != null) {
		const qty = Number(body.quantity_total)
		if (!Number.isFinite(qty) || qty < 0) return json({ ok: false, error: 'Invalid quantity_total' }, { status: 400 })
		if (Math.trunc(qty) < Number(before.quantity_sold ?? 0)) {
			return json({ ok: false, error: 'quantity_total cannot be < quantity_sold' }, { status: 400 })
		}
		patch.quantity_total = Math.trunc(qty)
	}
	if ('sales_start_at' in body) patch.sales_start_at = body.sales_start_at ?? null
	if ('sales_end_at' in body) patch.sales_end_at = body.sales_end_at ?? null
	if (body.is_active != null) patch.is_active = Boolean(body.is_active)

	if (!Object.keys(patch).length) return json({ ok: false, error: 'No changes' }, { status: 400 })

	const { data: updated, error } = await supabase
		.from('ticketing_ticket_types')
		.update(patch)
		.eq('id', id)
		.select('id,event_id,name,description,price_cents,currency_code,quantity_total,quantity_sold,sales_start_at,sales_end_at,is_active,created_at,updated_at')
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Update failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'tickets.type.update',
		target_type: 'ticket_type',
		target_id: id,
		before_state: before as any,
		after_state: updated as any,
		meta: { module: 'events', event_id: (before as any).event_id },
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
		.from('ticketing_ticket_types')
		.select('id,event_id,name,price_cents,currency_code,quantity_total,quantity_sold')
		.eq('id', id)
		.maybeSingle()
	if (beforeErr) return json({ ok: false, error: String(beforeErr.message ?? 'Query failed') }, { status: 500 })
	if (!before) return json({ ok: false, error: 'Not found' }, { status: 404 })

	if ((before.quantity_sold ?? 0) > 0) {
		return json({ ok: false, error: 'Cannot delete a ticket type that has sales.' }, { status: 400 })
	}

	const { error } = await supabase.from('ticketing_ticket_types').delete().eq('id', id)
	if (error) return json({ ok: false, error: String(error.message ?? 'Delete failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'tickets.type.delete',
		target_type: 'ticket_type',
		target_id: id,
		before_state: before as any,
		after_state: null,
		meta: { module: 'events', event_id: (before as any).event_id },
		req,
	})

	return json({ ok: true })
}
