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

	const { id: eventId } = await params
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data, error } = await supabase
		.from('ticketing_ticket_types')
		.select('id,event_id,name,description,price_cents,currency_code,quantity_total,quantity_sold,sales_start_at,sales_end_at,is_active,created_at,updated_at')
		.eq('event_id', eventId)
		.order('created_at', { ascending: true })

	if (error) return json({ ok: false, error: String(error.message ?? 'Query failed') }, { status: 500 })
	return json({ ok: true, data: data ?? [] })
}

type CreateBody = {
	name: string
	description?: string | null
	price_cents: number
	currency_code?: string
	quantity_total: number
	sales_start_at?: string | null
	sales_end_at?: string | null
	is_active?: boolean
}

export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const { id: eventId } = await params
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as CreateBody | null
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid body' }, { status: 400 })

	const name = String(body.name ?? '').trim()
	if (!name) return json({ ok: false, error: 'name is required' }, { status: 400 })

	const price = Number(body.price_cents)
	if (!Number.isFinite(price) || price < 0) return json({ ok: false, error: 'Invalid price_cents' }, { status: 400 })

	const qty = Number(body.quantity_total)
	if (!Number.isFinite(qty) || qty < 0) return json({ ok: false, error: 'Invalid quantity_total' }, { status: 400 })

	const currency = String(body.currency_code ?? 'USD').trim().toUpperCase() || 'USD'
	if (!/^[A-Z]{3}$/.test(currency)) return json({ ok: false, error: 'Invalid currency_code' }, { status: 400 })

	const payload = {
		event_id: eventId,
		name,
		description: body.description ?? null,
		price_cents: Math.trunc(price),
		currency_code: currency,
		quantity_total: Math.trunc(qty),
		sales_start_at: body.sales_start_at ?? null,
		sales_end_at: body.sales_end_at ?? null,
		is_active: Boolean(body.is_active ?? true),
	}

	const { data: created, error } = await supabase
		.from('ticketing_ticket_types')
		.insert(payload)
		.select('id,event_id,name,description,price_cents,currency_code,quantity_total,quantity_sold,sales_start_at,sales_end_at,is_active,created_at,updated_at')
		.single()

	if (error) return json({ ok: false, error: String(error.message ?? 'Insert failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'tickets.type.create',
		target_type: 'ticket_type',
		target_id: String((created as any)?.id ?? ''),
		before_state: null,
		after_state: created as any,
		meta: { module: 'events', event_id: eventId },
		req,
	})

	return json({ ok: true, data: created })
}
