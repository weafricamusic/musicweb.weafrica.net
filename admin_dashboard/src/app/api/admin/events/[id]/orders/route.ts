import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { assertPermission, getAdminContext } from '@/lib/admin/session'
import { logAdminAction } from '@/lib/admin/audit'
import { NextResponse } from 'next/server'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_events')
	} catch {
		return json({ ok: false, error: 'Forbidden' }, { status: 403 })
	}

	const { id: eventId } = await params
	const url = new URL(req.url)
	const limitRaw = url.searchParams.get('limit')
	const limit = Math.max(1, Math.min(200, Number(limitRaw ?? 100) || 100))

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data, error } = await supabase
		.from('ticketing_ticket_orders')
		.select('id,event_id,buyer_name,buyer_email,buyer_phone,status,payment_provider,payment_reference,total_amount_cents,currency_code,created_by_admin_email,created_at,updated_at')
		.eq('event_id', eventId)
		.order('created_at', { ascending: false })
		.limit(limit)

	if (error) return json({ ok: false, error: String(error.message ?? 'Query failed') }, { status: 500 })
	return json({ ok: true, data: data ?? [] })
}

type CreateBody = {
	buyer_name?: string | null
	buyer_email?: string | null
	buyer_phone?: string | null
	items: Array<{ ticket_type_id: string; quantity: number }>
	status?: 'pending' | 'paid' | 'cancelled' | 'refunded'
	payment_provider?: string | null
	payment_reference?: string | null
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
	if (!Array.isArray(body.items) || body.items.length === 0) return json({ ok: false, error: 'items is required' }, { status: 400 })

	const items = body.items.map((it) => ({
		ticket_type_id: String((it as any)?.ticket_type_id ?? ''),
		quantity: Number((it as any)?.quantity ?? 0),
	}))

	for (const it of items) {
		if (!it.ticket_type_id) return json({ ok: false, error: 'ticket_type_id is required' }, { status: 400 })
		if (!Number.isFinite(it.quantity) || it.quantity <= 0) return json({ ok: false, error: 'quantity must be > 0' }, { status: 400 })
		it.quantity = Math.trunc(it.quantity)
	}

	const rpcArgs = {
		p_event_id: eventId,
		p_buyer_name: body.buyer_name ?? null,
		p_buyer_email: body.buyer_email ?? null,
		p_buyer_phone: body.buyer_phone ?? null,
		p_items: items,
		p_status: body.status ?? 'paid',
		p_payment_provider: body.payment_provider ?? null,
		p_payment_reference: body.payment_reference ?? null,
		p_created_by_admin_email: ctx.admin.email,
	}

	const { data: orderId, error } = await supabase.rpc('ticketing_create_order', rpcArgs as any)
	if (error) return json({ ok: false, error: String(error.message ?? 'Order create failed') }, { status: 400 })

	await logAdminAction({
		ctx,
		action: 'tickets.order.create',
		target_type: 'ticket_order',
		target_id: String(orderId ?? ''),
		before_state: null,
		after_state: rpcArgs as any,
		meta: { module: 'events', event_id: eventId },
		req,
	})

	return json({ ok: true, data: { id: orderId } })
}
