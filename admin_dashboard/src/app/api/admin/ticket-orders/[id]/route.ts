import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { assertPermission, getAdminContext } from '@/lib/admin/session'
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

	const { data: order, error: orderErr } = await supabase
		.from('ticketing_ticket_orders')
		.select('id,event_id,buyer_name,buyer_email,buyer_phone,status,payment_provider,payment_reference,total_amount_cents,currency_code,created_by_admin_email,created_at,updated_at')
		.eq('id', id)
		.maybeSingle()
	if (orderErr) return json({ ok: false, error: String(orderErr.message ?? 'Query failed') }, { status: 500 })
	if (!order) return json({ ok: false, error: 'Not found' }, { status: 404 })

	const { data: items, error: itemsErr } = await supabase
		.from('ticketing_ticket_order_items')
		.select('id,order_id,ticket_type_id,ticket_type_name,quantity,unit_price_cents,line_total_cents,created_at')
		.eq('order_id', id)
		.order('created_at', { ascending: true })
	if (itemsErr) return json({ ok: false, error: String(itemsErr.message ?? 'Query failed') }, { status: 500 })

	const { data: tickets, error: ticketsErr } = await supabase
		.from('ticketing_tickets')
		.select('id,event_id,ticket_type_id,order_id,code,status,issued_at,checked_in_at,scanned_by_admin_email')
		.eq('order_id', id)
		.order('issued_at', { ascending: true })
	if (ticketsErr) return json({ ok: false, error: String(ticketsErr.message ?? 'Query failed') }, { status: 500 })

	return json({ ok: true, data: { order, items: items ?? [], tickets: tickets ?? [] } })
}
