import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { getCountryConfigByCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function normalizeCode(raw: string): string {
	const v = (raw ?? '').trim().toUpperCase()
	return /^[A-Z]{2}$/.test(v) ? v : 'MW'
}

function safeJsonParse(input: string): { ok: true; value: unknown } | { ok: false; error: string } {
	try {
		if (!input.trim()) return { ok: true, value: null }
		return { ok: true, value: JSON.parse(input) }
	} catch (e) {
		return { ok: false, error: e instanceof Error ? e.message : 'Invalid JSON' }
	}
}

export default async function CountryDetailPage(props: { params: Promise<{ code: string }>; searchParams?: Promise<{ ok?: string; error?: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const isOps = ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin'
	if (!isOps) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Only Ops and Super Admin can manage country configuration.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}

	const { code: rawCode } = await props.params
	const code = normalizeCode(rawCode)
	const sp = (props.searchParams ? await props.searchParams : {}) ?? {}

	const country = await getCountryConfigByCode(code)
	const supabaseAdmin = tryCreateSupabaseAdminClient()

	async function updateCountry(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const isOps = ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin'
		if (!isOps) redirect(`/admin/countries/${encodeURIComponent(code)}?error=forbidden`)

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect(`/admin/countries/${encodeURIComponent(code)}?error=service_role_required`)

		const patch: Record<string, unknown> = {}

		const currency_code = String(formData.get('currency_code') ?? '').trim().toUpperCase()
		const currency_symbol = String(formData.get('currency_symbol') ?? '').trim()
		const coin_rate = String(formData.get('coin_rate') ?? '').trim()
		const min_payout_amount = String(formData.get('min_payout_amount') ?? '').trim()
		const payment_methods_raw = String(formData.get('payment_methods') ?? '').trim()

		const live_stream_enabled = String(formData.get('live_stream_enabled') ?? '').trim()
		const ads_enabled = String(formData.get('ads_enabled') ?? '').trim()
		const premium_enabled = String(formData.get('premium_enabled') ?? '').trim()
		const is_active = String(formData.get('is_active') ?? '').trim()

		if (currency_code) patch.currency_code = currency_code
		if (currency_symbol) patch.currency_symbol = currency_symbol
		if (coin_rate) patch.coin_rate = Number(coin_rate)
		if (min_payout_amount) patch.min_payout_amount = Number(min_payout_amount)

		if (live_stream_enabled) patch.live_stream_enabled = live_stream_enabled === 'true'
		if (ads_enabled) patch.ads_enabled = ads_enabled === 'true'
		if (premium_enabled) patch.premium_enabled = premium_enabled === 'true'
		if (is_active) patch.is_active = is_active === 'true'

		const parsed = safeJsonParse(payment_methods_raw)
		if (!parsed.ok) redirect(`/admin/countries/${encodeURIComponent(code)}?error=${encodeURIComponent('invalid_payment_methods_json')}`)
		if (payment_methods_raw) patch.payment_methods = parsed.value

		// Load minimal before state
		let before: Record<string, unknown> | null = null
		try {
			let data: Record<string, unknown> | null = null
			// Prefer `country_code`, fall back to legacy `code`.
			const primary = await supabase
				.from('countries')
				.select('currency_code,currency_symbol,coin_rate,min_payout_amount,payment_methods,live_stream_enabled,ads_enabled,premium_enabled,is_active')
				.eq('country_code', code)
				.limit(1)
				.maybeSingle<Record<string, unknown>>()
			data = (primary.data ?? null) as Record<string, unknown> | null
			if (!data && primary.error && /country_code/i.test(primary.error.message ?? '')) {
				const legacy = await supabase
					.from('countries')
					.select('currency_code,currency_symbol,coin_rate,min_payout_amount,payment_methods,live_stream_enabled,ads_enabled,premium_enabled,is_active')
					.eq('code', code)
					.limit(1)
					.maybeSingle<Record<string, unknown>>()
				data = (legacy.data ?? null) as Record<string, unknown> | null
			}
			before = data
		} catch {
			before = null
		}

		try {
			let error: { message?: string } | null = null
			// Prefer `country_code`, fall back to legacy `code`.
			const primary = await supabase.from('countries').update(patch).eq('country_code', code)
			error = primary.error ? { message: primary.error.message } : null
			if (primary.error && /country_code/i.test(primary.error.message ?? '')) {
				const legacy = await supabase.from('countries').update(patch).eq('code', code)
				error = legacy.error ? { message: legacy.error.message } : null
			}
			if (error) throw new Error(error.message ?? 'update_failed')

			await logAdminAction({
				ctx,
				action: 'country.update',
				target_type: 'country',
				target_id: code,
				before_state: before,
				after_state: patch,
				meta: { module: 'country_feature_control' },
			})

			redirect(`/admin/countries/${encodeURIComponent(code)}?ok=1`)
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'update_failed'
			redirect(`/admin/countries/${encodeURIComponent(code)}?error=${encodeURIComponent(msg)}`)
		}
	}

	return (
		<div className="space-y-6">
			<div className="flex items-start justify-between gap-4">
				<div>
					<h1 className="text-2xl font-bold">{country?.country_name ?? code}</h1>
					<p className="mt-1 text-sm text-gray-400">Country code: {code}</p>
				</div>
				<div className="flex gap-2">
					<Link href="/admin/countries" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						All countries
					</Link>
					<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Ads & promotions
					</Link>
				</div>
			</div>

			{!supabaseAdmin ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
					<b>Service role required:</b> set <code>SUPABASE_SERVICE_ROLE_KEY</code> to edit country settings.
				</div>
			) : null}

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved.</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Update failed: {sp.error}
				</div>
			) : null}

			<div className="grid gap-4 md:grid-cols-2">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Current Configuration</h2>
					<div className="mt-4 space-y-2 text-sm">
						<Row label="Currency" value={`${country?.currency_code ?? '—'} ${country?.currency_symbol ?? ''}`.trim()} />
						<Row label="Coin Rate" value={String(country?.coin_rate ?? '—')} />
						<Row label="Min Payout" value={String(country?.min_payout_amount ?? '—')} />
						<Row label="Live Streaming" value={country ? (country.live_stream_enabled ? 'Enabled' : 'Disabled') : '—'} />
						<Row label="Ads" value={country ? (country.ads_enabled ? 'Enabled' : 'Disabled') : '—'} />
						<Row label="Premium" value={country ? (country.premium_enabled ? 'Enabled' : 'Disabled') : '—'} />
						<Row label="Country Status" value={country ? (country.is_active ? 'Active' : 'Disabled') : '—'} />
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Edit (Ops/Super)</h2>
					<p className="mt-1 text-sm text-gray-400">Changes are logged to Admin Logs.</p>

					<form action={updateCountry} className="mt-4 space-y-4">
						<div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
							<Field label="Currency Code" name="currency_code" defaultValue={country?.currency_code ?? ''} placeholder="MWK" />
							<Field label="Currency Symbol" name="currency_symbol" defaultValue={country?.currency_symbol ?? ''} placeholder="MK" />
							<Field label="Coin Rate" name="coin_rate" defaultValue={country?.coin_rate != null ? String(country.coin_rate) : ''} placeholder="100" />
							<Field label="Min Payout" name="min_payout_amount" defaultValue={country?.min_payout_amount != null ? String(country.min_payout_amount) : ''} placeholder="5000" />
						</div>

						<div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
							<Select
								label="Live Streaming"
								name="live_stream_enabled"
								defaultValue={country ? String(country.live_stream_enabled) : ''}
								options={[
									{ label: 'No change', value: '' },
									{ label: 'Enabled', value: 'true' },
									{ label: 'Disabled', value: 'false' },
								]}
							/>
							<Select
								label="Ads"
								name="ads_enabled"
								defaultValue={country ? String(country.ads_enabled) : ''}
								options={[
									{ label: 'No change', value: '' },
									{ label: 'Enabled', value: 'true' },
									{ label: 'Disabled', value: 'false' },
								]}
							/>
							<Select
								label="Premium"
								name="premium_enabled"
								defaultValue={country ? String(country.premium_enabled) : ''}
								options={[
									{ label: 'No change', value: '' },
									{ label: 'Enabled', value: 'true' },
									{ label: 'Disabled', value: 'false' },
								]}
							/>
							<Select
								label="Country Status"
								name="is_active"
								defaultValue={country ? String(country.is_active) : ''}
								options={[
									{ label: 'No change', value: '' },
									{ label: 'Active', value: 'true' },
									{ label: 'Disabled', value: 'false' },
								]}
							/>
						</div>

						<div>
							<label className="block text-sm text-gray-300">Payment Methods (JSON)</label>
							<textarea
								name="payment_methods"
								defaultValue={country?.payment_methods ? JSON.stringify(country.payment_methods, null, 2) : ''}
								placeholder='{"airtel_money": true, "mpamba": true}'
								rows={6}
								className="mt-2 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none"
							/>
							<p className="mt-1 text-xs text-gray-400">Leave empty to keep existing value.</p>
						</div>

						<button
							type="submit"
							disabled={!supabaseAdmin}
							className="h-10 rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5 disabled:opacity-60"
						>
							Save changes
						</button>
					</form>
				</div>
			</div>
		</div>
	)
}

function Row(props: { label: string; value: string }) {
	return (
		<div className="flex items-center justify-between gap-4">
			<span className="text-gray-400">{props.label}</span>
			<span className="font-medium">{props.value || '—'}</span>
		</div>
	)
}

function Field(props: { label: string; name: string; defaultValue: string; placeholder?: string }) {
	return (
		<label className="block">
			<span className="block text-sm text-gray-300">{props.label}</span>
			<input
				name={props.name}
				defaultValue={props.defaultValue}
				placeholder={props.placeholder}
				className="mt-2 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none"
			/>
		</label>
	)
}

function Select(props: { label: string; name: string; defaultValue: string; options: { label: string; value: string }[] }) {
	return (
		<label className="block">
			<span className="block text-sm text-gray-300">{props.label}</span>
			<select
				name={props.name}
				defaultValue={props.defaultValue}
				className="mt-2 h-10 w-full rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none"
			>
				{props.options.map((o) => (
					<option key={o.value || o.label} value={o.value}>
						{o.label}
					</option>
				))}
			</select>
		</label>
	)
}
