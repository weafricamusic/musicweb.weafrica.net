'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'

type EventRow = {
	id: string
	title: string
	description: string | null
	cover_image_url: string
	venue_name: string | null
	venue_address: string | null
	city: string | null
	country_code: string | null
	starts_at: string
	ends_at: string | null
	timezone: string
	status: 'draft' | 'published' | 'cancelled'
	created_by_admin_email: string | null
	created_at: string
	updated_at: string
}

type TicketTypeRow = {
	id: string
	event_id: string
	name: string
	description: string | null
	price_cents: number
	currency_code: string
	quantity_total: number
	quantity_sold: number
	sales_start_at: string | null
	sales_end_at: string | null
	is_active: boolean
	created_at: string
	updated_at: string
}

type OrderRow = {
	id: string
	event_id: string
	buyer_name: string | null
	buyer_email: string | null
	buyer_phone: string | null
	status: 'pending' | 'paid' | 'cancelled' | 'refunded'
	payment_provider: string | null
	payment_reference: string | null
	total_amount_cents: number
	currency_code: string
	created_by_admin_email: string | null
	created_at: string
	updated_at: string
}

type OrderDetail = {
	order: OrderRow
	items: Array<{
		id: string
		order_id: string
		ticket_type_id: string
		ticket_type_name: string
		quantity: number
		unit_price_cents: number
		line_total_cents: number
		created_at: string
	}>
	tickets: Array<{
		id: string
		event_id: string
		ticket_type_id: string
		order_id: string
		code: string
		status: 'issued' | 'voided' | 'checked_in'
		issued_at: string
		checked_in_at: string | null
		scanned_by_admin_email: string | null
	}>
}

type ApiEvent = { ok: true; data: EventRow } | { ok: false; error: string }

type ApiTicketTypes = { ok: true; data: TicketTypeRow[] } | { ok: false; error: string }

type ApiOrders = { ok: true; data: OrderRow[] } | { ok: false; error: string }

type ApiOrderDetail = { ok: true; data: OrderDetail } | { ok: false; error: string }

type ApiOk = { ok: true } | { ok: false; error: string }

type ApiOrderCreate = { ok: true; data: { id: string } } | { ok: false; error: string }

function isoToLocalInput(value: string | null): string {
	if (!value) return ''
	const d = new Date(value)
	if (Number.isNaN(d.getTime())) return ''
	const pad = (n: number) => String(n).padStart(2, '0')
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

function localInputToIso(value: string): string | null {
	const v = value.trim()
	if (!v) return null
	const d = new Date(v)
	return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

function fmtDate(iso: string | null) {
	if (!iso) return '—'
	const d = new Date(iso)
	return Number.isNaN(d.getTime()) ? iso : d.toLocaleString()
}

function money(cents: number, currency: string) {
	return `${currency} ${(cents / 100).toFixed(2)}`
}

export default function EventDetailPage() {
	const params = useParams()
	const rawId = (params as { id?: string | string[] })?.id
	const eventId = Array.isArray(rawId) ? rawId[0] : rawId

	const [event, setEvent] = useState<EventRow | null>(null)
	const [ticketTypes, setTicketTypes] = useState<TicketTypeRow[]>([])
	const [orders, setOrders] = useState<OrderRow[]>([])
	const [orderDetail, setOrderDetail] = useState<OrderDetail | null>(null)
	const [error, setError] = useState<string | null>(null)
	const [ok, setOk] = useState<string | null>(null)
	const [busy, setBusy] = useState(false)
	const [uploadBusy, setUploadBusy] = useState(false)
	const [coverPreview, setCoverPreview] = useState<string | null>(null)

	const loadAll = useCallback(async () => {
		if (!eventId) return
		setError(null)
		try {
			const [eventRes, typesRes, ordersRes] = await Promise.all([
				fetch(`/api/admin/events/${encodeURIComponent(eventId)}`),
				fetch(`/api/admin/events/${encodeURIComponent(eventId)}/ticket-types`),
				fetch(`/api/admin/events/${encodeURIComponent(eventId)}/orders?limit=200`),
			])
			const eventJson = (await eventRes.json().catch(() => null)) as ApiEvent | null
			const typesJson = (await typesRes.json().catch(() => null)) as ApiTicketTypes | null
			const ordersJson = (await ordersRes.json().catch(() => null)) as ApiOrders | null

			if (!eventJson || !typesJson || !ordersJson) {
				setError('Failed to load event data.')
				return
			}
			if (!eventRes.ok || eventJson.ok === false) {
				setError(eventJson.ok === false ? eventJson.error : `Event request failed (${eventRes.status}).`)
				return
			}
			if (!typesRes.ok || typesJson.ok === false) {
				setError(typesJson.ok === false ? typesJson.error : `Ticket types request failed (${typesRes.status}).`)
				return
			}
			if (!ordersRes.ok || ordersJson.ok === false) {
				setError(ordersJson.ok === false ? ordersJson.error : `Orders request failed (${ordersRes.status}).`)
				return
			}

			setEvent(eventJson.data)
			setTicketTypes(typesJson.data)
			setOrders(ordersJson.data)
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Request failed.')
		}
	}, [eventId])

	useEffect(() => {
		void loadAll()
	}, [loadAll])

	const [editState, setEditState] = useState({
		title: '',
		description: '',
		cover_image_url: '',
		venue_name: '',
		venue_address: '',
		city: '',
		country_code: '',
		starts_at: '',
		ends_at: '',
		timezone: 'UTC',
		status: 'draft' as EventRow['status'],
	})

	useEffect(() => {
		if (!event) return
		setEditState({
			title: event.title,
			description: event.description ?? '',
			cover_image_url: event.cover_image_url ?? '',
			venue_name: event.venue_name ?? '',
			venue_address: event.venue_address ?? '',
			city: event.city ?? '',
			country_code: event.country_code ?? '',
			starts_at: isoToLocalInput(event.starts_at),
			ends_at: isoToLocalInput(event.ends_at),
			timezone: event.timezone ?? 'UTC',
			status: event.status,
		})
	}, [event])

	async function uploadCover(file: File) {
		setOk(null)
		setError(null)
		setUploadBusy(true)
		try {
			if (coverPreview) URL.revokeObjectURL(coverPreview)
			setCoverPreview(URL.createObjectURL(file))

			const form = new FormData()
			form.set('file', file)
			const res = await fetch('/api/admin/events/cover/upload', { method: 'POST', body: form })
			const json = (await res.json().catch(() => null)) as
				| { ok: true; public_url: string | null; signed_url: string | null }
				| { ok?: false; error?: unknown }
				| null

			if (!json) {
				setError(`Upload failed (status ${res.status}).`)
				return
			}
			if (!res.ok || (json as any).ok === false) {
				setError(String((json as any).error ?? `Upload failed (status ${res.status}).`))
				return
			}

			const url = (json as any).public_url || (json as any).signed_url || ''
			setEditState((s) => ({ ...s, cover_image_url: String(url || '') }))
			setOk('Cover image uploaded. Click “Save changes” to persist.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Upload failed.')
		} finally {
			setUploadBusy(false)
		}
	}

	const [typeForm, setTypeForm] = useState({
		name: '',
		description: '',
		price_cents: '0',
		currency_code: 'USD',
		quantity_total: '0',
		sales_start_at: '',
		sales_end_at: '',
		is_active: true,
	})

	const [orderForm, setOrderForm] = useState({
		buyer_name: '',
		buyer_email: '',
		buyer_phone: '',
		payment_provider: '',
		payment_reference: '',
		status: 'paid' as OrderRow['status'],
		items: [{ ticket_type_id: '', quantity: '1' }],
	})

	const ticketTypeOptions = useMemo(() => ticketTypes, [ticketTypes])

	async function saveEvent() {
		if (!eventId) return
		setError(null)
		setOk(null)
		setBusy(true)
		try {
			const startsIso = localInputToIso(editState.starts_at)
			const endsIso = localInputToIso(editState.ends_at)
			if (!startsIso) {
				setError('Valid starts_at is required.')
				return
			}
			if (editState.ends_at && !endsIso) {
				setError('Invalid ends_at date/time.')
				return
			}

			const res = await fetch(`/api/admin/events/${encodeURIComponent(eventId)}`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					title: editState.title.trim(),
					description: editState.description.trim() || null,
					cover_image_url: editState.cover_image_url.trim(),
					venue_name: editState.venue_name.trim() || null,
					venue_address: editState.venue_address.trim() || null,
					city: editState.city.trim() || null,
					country_code: editState.country_code.trim() || null,
					starts_at: startsIso,
					ends_at: endsIso,
					timezone: editState.timezone.trim() || 'UTC',
					status: editState.status,
				}),
			})
			const json = (await res.json().catch(() => null)) as ApiEvent | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || json.ok === false) {
				setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setEvent(json.data)
			setOk('Event updated.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Update failed.')
		} finally {
			setBusy(false)
		}
	}

	async function createTicketType() {
		if (!eventId) return
		setError(null)
		setOk(null)
		setBusy(true)
		try {
			const price = Number(typeForm.price_cents)
			const qty = Number(typeForm.quantity_total)
			if (!typeForm.name.trim()) {
				setError('Ticket type name is required.')
				return
			}
			if (!Number.isFinite(price) || price < 0) {
				setError('Invalid price.')
				return
			}
			if (!Number.isFinite(qty) || qty < 0) {
				setError('Invalid quantity.')
				return
			}

			const res = await fetch(`/api/admin/events/${encodeURIComponent(eventId)}/ticket-types`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					name: typeForm.name.trim(),
					description: typeForm.description.trim() || null,
					price_cents: Math.trunc(price),
					currency_code: typeForm.currency_code.trim().toUpperCase() || 'USD',
					quantity_total: Math.trunc(qty),
					sales_start_at: localInputToIso(typeForm.sales_start_at),
					sales_end_at: localInputToIso(typeForm.sales_end_at),
					is_active: typeForm.is_active,
				}),
			})
			const json = (await res.json().catch(() => null)) as ApiTicketTypes | ApiOk | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || json.ok === false) {
				setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			await loadAll()
			setTypeForm({
				name: '',
				description: '',
				price_cents: '0',
				currency_code: typeForm.currency_code || 'USD',
				quantity_total: '0',
				sales_start_at: '',
				sales_end_at: '',
				is_active: true,
			})
			setOk('Ticket type created.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Create failed.')
		} finally {
			setBusy(false)
		}
	}

	async function createOrder() {
		if (!eventId) return
		setError(null)
		setOk(null)
		setBusy(true)
		try {
			const items = orderForm.items
				.map((item) => ({
					ticket_type_id: item.ticket_type_id,
					quantity: Number(item.quantity),
				}))
				.filter((item) => item.ticket_type_id && Number.isFinite(item.quantity) && item.quantity > 0)

			if (!items.length) {
				setError('At least one ticket item is required.')
				return
			}

			const res = await fetch(`/api/admin/events/${encodeURIComponent(eventId)}/orders`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					buyer_name: orderForm.buyer_name.trim() || null,
					buyer_email: orderForm.buyer_email.trim() || null,
					buyer_phone: orderForm.buyer_phone.trim() || null,
					items,
					status: orderForm.status,
					payment_provider: orderForm.payment_provider.trim() || null,
					payment_reference: orderForm.payment_reference.trim() || null,
				}),
			})
			const json = (await res.json().catch(() => null)) as ApiOrderCreate | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || json.ok === false) {
				setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
				return
			}

			await loadAll()
			setOrderForm({
				buyer_name: '',
				buyer_email: '',
				buyer_phone: '',
				payment_provider: '',
				payment_reference: '',
				status: 'paid',
				items: [{ ticket_type_id: '', quantity: '1' }],
			})
			setOk('Ticket order created.')
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Create failed.')
		} finally {
			setBusy(false)
		}
	}

	async function loadOrderDetail(orderId: string) {
		setError(null)
		setBusy(true)
		try {
			const res = await fetch(`/api/admin/ticket-orders/${encodeURIComponent(orderId)}`)
			const json = (await res.json().catch(() => null)) as ApiOrderDetail | null
			if (!json) {
				setError(`Request failed (status ${res.status}).`)
				return
			}
			if (!res.ok || json.ok === false) {
				setError(json.ok === false ? json.error : `Request failed (status ${res.status}).`)
				return
			}
			setOrderDetail(json.data)
		} catch (e: unknown) {
			setError(e instanceof Error ? e.message : 'Request failed.')
		} finally {
			setBusy(false)
		}
	}

	if (!eventId) return null

	return (
		<div className="space-y-8">
			<div className="flex items-start justify-between gap-4">
				<div>
					<h1 className="text-2xl font-bold">Event</h1>
					<p className="mt-1 text-sm text-gray-400">Manage event details, ticket types, and orders.</p>
				</div>
				<Link href="/admin/events" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			{error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{error}</div> : null}
			{ok ? <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">{ok}</div> : null}

			{event ? (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<div className="grid gap-4 md:grid-cols-2">
						<div className="md:col-span-2">
							<label className="text-xs text-gray-400">Title</label>
							<input
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={editState.title}
								onChange={(e) => setEditState((s) => ({ ...s, title: e.target.value }))}
							/>
						</div>

						<div className="md:col-span-2">
							<label className="text-xs text-gray-400">Description</label>
							<textarea
								rows={4}
								className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
								value={editState.description}
								onChange={(e) => setEditState((s) => ({ ...s, description: e.target.value }))}
							/>
						</div>

						<div className="md:col-span-2">
							<label className="text-xs text-gray-400">Cover image</label>
							<div className="mt-1 flex items-center gap-3">
								<input
									type="file"
									accept="image/png,image/jpeg,image/webp"
									disabled={busy || uploadBusy}
									onChange={(e) => {
										const f = e.target.files?.[0]
										if (f) void uploadCover(f)
										e.currentTarget.value = ''
									}}
									className="block w-full text-sm text-gray-200 file:mr-4 file:rounded-xl file:border-0 file:bg-white file:px-4 file:py-2 file:text-sm file:font-medium file:text-black hover:file:bg-white/90"
								/>
								{editState.cover_image_url ? (
									<button
										type="button"
										onClick={() => setEditState((s) => ({ ...s, cover_image_url: '' }))}
										disabled={busy || uploadBusy}
										className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60"
									>
										Remove
									</button>
								) : null}
							</div>
							{uploadBusy ? <div className="mt-2 text-xs text-gray-400">Uploading…</div> : null}
							{coverPreview || editState.cover_image_url ? (
								<img src={coverPreview ?? editState.cover_image_url} alt="Cover" className="mt-3 h-40 w-full rounded-xl object-cover border border-white/10" />
							) : null}
						</div>

						<div>
							<label className="text-xs text-gray-400">Venue name</label>
							<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.venue_name} onChange={(e) => setEditState((s) => ({ ...s, venue_name: e.target.value }))} />
						</div>
						<div>
							<label className="text-xs text-gray-400">Venue address</label>
							<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.venue_address} onChange={(e) => setEditState((s) => ({ ...s, venue_address: e.target.value }))} />
						</div>
						<div>
							<label className="text-xs text-gray-400">City</label>
							<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.city} onChange={(e) => setEditState((s) => ({ ...s, city: e.target.value }))} />
						</div>
						<div>
							<label className="text-xs text-gray-400">Country code</label>
							<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm uppercase outline-none focus:border-white/20" value={editState.country_code} onChange={(e) => setEditState((s) => ({ ...s, country_code: e.target.value }))} />
						</div>

						<div>
							<label className="text-xs text-gray-400">Starts at</label>
							<input type="datetime-local" className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.starts_at} onChange={(e) => setEditState((s) => ({ ...s, starts_at: e.target.value }))} />
						</div>
						<div>
							<label className="text-xs text-gray-400">Ends at</label>
							<input type="datetime-local" className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.ends_at} onChange={(e) => setEditState((s) => ({ ...s, ends_at: e.target.value }))} />
						</div>

						<div>
							<label className="text-xs text-gray-400">Timezone</label>
							<input className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.timezone} onChange={(e) => setEditState((s) => ({ ...s, timezone: e.target.value }))} />
						</div>
						<div>
							<label className="text-xs text-gray-400">Status</label>
							<select className="mt-1 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={editState.status} onChange={(e) => setEditState((s) => ({ ...s, status: e.target.value as EventRow['status'] }))}>
								<option value="draft">draft</option>
								<option value="published">published</option>
								<option value="cancelled">cancelled</option>
							</select>
						</div>

						<div className="md:col-span-2 flex items-center justify-end gap-3">
							<button
								type="button"
								onClick={saveEvent}
								disabled={busy || uploadBusy}
								className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60"
							>
								{busy ? 'Saving…' : 'Save changes'}
							</button>
						</div>
					</div>
				</div>
			) : (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6 text-sm text-gray-400">Loading event…</div>
			)}

			<div className="grid gap-6 lg:grid-cols-2">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-lg font-semibold">Ticket types</h2>
					<p className="mt-1 text-sm text-gray-400">Define inventory and pricing.</p>

					<div className="mt-4 space-y-3">
						{ticketTypes.length ? (
							ticketTypes.map((t) => (
								<div key={t.id} className="rounded-xl border border-white/10 bg-black/20 p-3 text-sm">
									<div className="flex items-center justify-between">
										<div className="font-medium">{t.name}</div>
										<div className="text-xs text-gray-400">{t.is_active ? 'Active' : 'Inactive'}</div>
									</div>
									<div className="mt-1 text-xs text-gray-400">{money(t.price_cents, t.currency_code)} · {t.quantity_sold}/{t.quantity_total} sold</div>
									<div className="mt-1 text-xs text-gray-500">Sales: {fmtDate(t.sales_start_at)} → {fmtDate(t.sales_end_at)}</div>
								</div>
							))
						) : (
							<div className="text-sm text-gray-400">No ticket types yet.</div>
						)}
					</div>

					<div className="mt-6 border-t border-white/10 pt-4">
						<h3 className="text-sm font-semibold">Create ticket type</h3>
						<div className="mt-3 grid gap-3 md:grid-cols-2">
							<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Name" value={typeForm.name} onChange={(e) => setTypeForm((s) => ({ ...s, name: e.target.value }))} />
							<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Price (cents)" value={typeForm.price_cents} onChange={(e) => setTypeForm((s) => ({ ...s, price_cents: e.target.value }))} />
							<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Currency (USD)" value={typeForm.currency_code} onChange={(e) => setTypeForm((s) => ({ ...s, currency_code: e.target.value }))} />
							<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Quantity" value={typeForm.quantity_total} onChange={(e) => setTypeForm((s) => ({ ...s, quantity_total: e.target.value }))} />
							<input type="datetime-local" className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={typeForm.sales_start_at} onChange={(e) => setTypeForm((s) => ({ ...s, sales_start_at: e.target.value }))} />
							<input type="datetime-local" className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={typeForm.sales_end_at} onChange={(e) => setTypeForm((s) => ({ ...s, sales_end_at: e.target.value }))} />
							<textarea className="md:col-span-2 rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Description" value={typeForm.description} onChange={(e) => setTypeForm((s) => ({ ...s, description: e.target.value }))} />
							<label className="md:col-span-2 inline-flex items-center gap-2 text-sm text-gray-200">
								<input type="checkbox" checked={typeForm.is_active} onChange={(e) => setTypeForm((s) => ({ ...s, is_active: e.target.checked }))} className="h-4 w-4 rounded border border-white/20 bg-black/20" />
								Active
							</label>
						</div>
						<div className="mt-4 flex justify-end">
							<button type="button" onClick={createTicketType} disabled={busy} className="inline-flex h-9 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60">
								{busy ? 'Saving…' : 'Add ticket type'}
							</button>
						</div>
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-lg font-semibold">Orders</h2>
					<p className="mt-1 text-sm text-gray-400">Sell tickets and view issued codes.</p>

					<div className="mt-4 space-y-3">
						{orders.length ? (
							orders.map((o) => (
								<div key={o.id} className="rounded-xl border border-white/10 bg-black/20 p-3 text-sm">
									<div className="flex items-center justify-between">
										<div className="font-medium">{o.buyer_name || o.buyer_email || 'Walk-in'}</div>
										<div className="text-xs text-gray-400">{fmtDate(o.created_at)}</div>
									</div>
									<div className="mt-1 text-xs text-gray-400">{money(o.total_amount_cents, o.currency_code)} · {o.status}</div>
									<button type="button" onClick={() => void loadOrderDetail(o.id)} className="mt-2 text-xs text-white/80 underline hover:text-white">View tickets</button>
								</div>
							))
						) : (
							<div className="text-sm text-gray-400">No orders yet.</div>
						)}
					</div>

					{orderDetail ? (
						<div className="mt-4 rounded-xl border border-white/10 bg-black/30 p-3 text-sm">
							<div className="flex items-center justify-between">
								<div className="font-medium">Order {orderDetail.order.id.slice(0, 8)}</div>
								<button type="button" onClick={() => setOrderDetail(null)} className="text-xs text-gray-400 hover:text-white">Close</button>
							</div>
							<div className="mt-2 text-xs text-gray-400">Tickets ({orderDetail.tickets.length})</div>
							<div className="mt-2 grid gap-2">
								{orderDetail.tickets.map((t) => (
									<div key={t.id} className="flex items-center justify-between rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-xs">
										<div>{t.code}</div>
										<div className="text-gray-400">{t.status}</div>
									</div>
								))}
							</div>
						</div>
					) : null}

					<div className="mt-6 border-t border-white/10 pt-4">
						<h3 className="text-sm font-semibold">Sell tickets</h3>
						<div className="mt-3 grid gap-3">
							<div className="grid gap-3 md:grid-cols-2">
								<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Buyer name" value={orderForm.buyer_name} onChange={(e) => setOrderForm((s) => ({ ...s, buyer_name: e.target.value }))} />
								<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Buyer email" value={orderForm.buyer_email} onChange={(e) => setOrderForm((s) => ({ ...s, buyer_email: e.target.value }))} />
								<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Buyer phone" value={orderForm.buyer_phone} onChange={(e) => setOrderForm((s) => ({ ...s, buyer_phone: e.target.value }))} />
								<select className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" value={orderForm.status} onChange={(e) => setOrderForm((s) => ({ ...s, status: e.target.value as OrderRow['status'] }))}>
									<option value="paid">paid</option>
									<option value="pending">pending</option>
									<option value="cancelled">cancelled</option>
									<option value="refunded">refunded</option>
								</select>
								<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Payment provider" value={orderForm.payment_provider} onChange={(e) => setOrderForm((s) => ({ ...s, payment_provider: e.target.value }))} />
								<input className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20" placeholder="Payment reference" value={orderForm.payment_reference} onChange={(e) => setOrderForm((s) => ({ ...s, payment_reference: e.target.value }))} />
							</div>

							<div className="space-y-2">
								{orderForm.items.map((item, idx) => (
									<div key={idx} className="grid gap-2 md:grid-cols-[1fr,120px,80px]">
										<select
											value={item.ticket_type_id}
											onChange={(e) => {
												const value = e.target.value
												setOrderForm((s) => ({
													...s,
													items: s.items.map((row, rIdx) => (rIdx === idx ? { ...row, ticket_type_id: value } : row)),
												}))
											}}
											className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
										>
											<option value="">Select ticket type</option>
											{ticketTypeOptions.map((t) => (
												<option key={t.id} value={t.id}>
													{t.name} ({money(t.price_cents, t.currency_code)})
												</option>
											))}
										</select>
										<input
											className="rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none focus:border-white/20"
											value={item.quantity}
											onChange={(e) => {
												const value = e.target.value
												setOrderForm((s) => ({
													...s,
													items: s.items.map((row, rIdx) => (rIdx === idx ? { ...row, quantity: value } : row)),
												}))
											}}
											placeholder="Qty"
										/>
										<button
											type="button"
											onClick={() => {
												setOrderForm((s) => ({
													...s,
													items: s.items.filter((_, rIdx) => rIdx !== idx),
												}))
											}}
											className="rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
											disabled={orderForm.items.length === 1}
										>
											Remove
										</button>
									</div>
								))}
								<button
									type="button"
									onClick={() => setOrderForm((s) => ({ ...s, items: [...s.items, { ticket_type_id: '', quantity: '1' }] }))}
									className="text-xs text-white/80 underline hover:text-white"
								>
									Add another ticket type
								</button>
							</div>
						</div>

						<div className="mt-4 flex justify-end">
							<button type="button" onClick={createOrder} disabled={busy} className="inline-flex h-9 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90 disabled:opacity-60">
								{busy ? 'Creating…' : 'Create order'}
							</button>
						</div>
					</div>
				</div>
			</div>
		</div>
	)
}
