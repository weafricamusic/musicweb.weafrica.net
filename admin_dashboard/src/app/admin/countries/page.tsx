import Link from 'next/link'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getSupabaseServerEnvDebug } from '@/lib/supabase/server'

export const runtime = 'nodejs'

type CountryRow = {
	country_code: string
	country_name: string
	currency_code?: string | null
	currency_symbol?: string | null
	coin_rate?: number | null
	min_payout_amount?: number | null
	live_stream_enabled?: boolean | null
	ads_enabled?: boolean | null
	premium_enabled?: boolean | null
	is_active?: boolean | null
}

function formatBool(v: unknown): string {
	return v ? 'On' : 'Off'
}

function getErrorMessage(e: unknown): string {
	if (e instanceof Error) return e.message
	if (e && typeof e === 'object' && 'message' in e) return String((e as { message?: unknown }).message ?? 'Failed to load countries')
	return 'Failed to load countries'
}

function findMissingColumn(message: string | undefined): string | null {
	const msg = String(message ?? '')
	let m = msg.match(/column \"([^\"]+)\" does not exist/i)
	if (m?.[1]) return m[1]
	m = msg.match(/could not find the '([^']+)' column/i)
	if (m?.[1]) return m[1]
	m = msg.match(/column ([a-z0-9_]+) does not exist/i)
	if (m?.[1]) return m[1]
	return null
}

async function trySelectWithFallback<T extends Record<string, unknown>>(args: {
	supabase: ReturnType<typeof tryCreateSupabaseAdminClient> & NonNullable<ReturnType<typeof tryCreateSupabaseAdminClient>>
	columns: string[]
	orderBy?: string
	limit?: number
}): Promise<{ rows: T[]; usedColumns: string[]; usedOrderBy: string | null; error: string | null }> {
	const limit = args.limit ?? 250
	let cols = [...args.columns]
	let orderBy = args.orderBy ?? null

	for (let attempt = 0; attempt < 12; attempt++) {
		const select = cols.join(',')
		let q = args.supabase.from('countries').select(select).limit(limit)
		if (orderBy && cols.includes(orderBy)) {
			q = q.order(orderBy, { ascending: true })
		}
		const { data, error } = await q
		if (!error) {
			return {
				rows: (data ?? []) as unknown as T[],
				usedColumns: cols,
				usedOrderBy: orderBy && cols.includes(orderBy) ? orderBy : null,
				error: null,
			}
		}

		const missing = findMissingColumn(error.message)
		if (missing && cols.includes(missing)) {
			cols = cols.filter((c) => c !== missing)
			if (orderBy === missing) orderBy = null
			continue
		}

		return { rows: [], usedColumns: cols, usedOrderBy: orderBy, error: error.message ?? 'Failed to load countries' }
	}

	return { rows: [], usedColumns: cols, usedOrderBy: orderBy, error: 'Failed to load countries (schema mismatch)' }
}

async function loadCountries(supabase: ReturnType<typeof tryCreateSupabaseAdminClient> & NonNullable<ReturnType<typeof tryCreateSupabaseAdminClient>>): Promise<{ rows: CountryRow[]; warning: string | null }> {
	// Preferred schema.
	const preferred = await trySelectWithFallback<CountryRow>({
		supabase,
		columns: [
			'country_code',
			'country_name',
			'currency_code',
			'currency_symbol',
			'coin_rate',
			'min_payout_amount',
			'live_stream_enabled',
			'ads_enabled',
			'premium_enabled',
			'is_active',
		],
		orderBy: 'country_name',
		limit: 250,
	})
	if (!preferred.error && preferred.rows.length) return { rows: preferred.rows, warning: null }

	// Legacy schema fallback: `code` + `name`.
	const legacy = await trySelectWithFallback<Record<string, unknown>>({
		supabase,
		columns: [
			'code',
			'name',
			'currency_code',
			'currency_symbol',
			'coin_rate',
			'min_payout_amount',
			'live_stream_enabled',
			'ads_enabled',
			'premium_enabled',
			'is_active',
		],
		orderBy: 'name',
		limit: 250,
	})
	if (legacy.error) {
		// If preferred failed with a real error, surface it; otherwise surface legacy.
		const msg = preferred.error ?? legacy.error
		throw new Error(msg)
	}

	const mapped = legacy.rows
		.map<CountryRow | null>((r) => {
			const code = String(r.code ?? '').trim().toUpperCase()
			const name = String(r.name ?? '').trim()
			if (!code || code.length !== 2) return null
			const out: CountryRow = {
				country_code: code,
				country_name: name || code,
				currency_code: (r.currency_code as string | null | undefined) ?? null,
				currency_symbol: (r.currency_symbol as string | null | undefined) ?? null,
				coin_rate: (typeof r.coin_rate === 'number' ? r.coin_rate : null) as number | null,
				min_payout_amount: (typeof r.min_payout_amount === 'number' ? r.min_payout_amount : null) as number | null,
				live_stream_enabled: (typeof r.live_stream_enabled === 'boolean' ? r.live_stream_enabled : null) as boolean | null,
				ads_enabled: (typeof r.ads_enabled === 'boolean' ? r.ads_enabled : null) as boolean | null,
				premium_enabled: (typeof r.premium_enabled === 'boolean' ? r.premium_enabled : null) as boolean | null,
				is_active: (typeof r.is_active === 'boolean' ? r.is_active : null) as boolean | null,
			}
			return out
		})
		.filter((v): v is CountryRow => v != null)

	return { rows: mapped, warning: 'Using legacy countries schema (code/name). Consider running the latest migrations.' }
}

export default async function CountriesPage() {
	const ctx = await getAdminContext()
	if (!ctx) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You are not an active admin.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}

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

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		const env = (() => {
			try {
				return getSupabaseServerEnvDebug()
			} catch {
				return null
			}
		})()
		return (
			<div className="space-y-6">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Country & Feature Control</h1>
					<p className="mt-1 text-sm text-gray-400">
						Configure currency, coin rate, payouts, feature flags, and ads per country.
					</p>
				</div>

				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					<div className="font-semibold">Service role required</div>
					<p className="mt-1">
						Set <code>SUPABASE_SERVICE_ROLE_KEY</code> (server-only) and restart/redeploy. Admin country config is
						 expected to bypass RLS.
					</p>
					{env ? (
						<p className="mt-2 text-xs text-amber-200/90">
							Env check: urlHost={env.urlHost} keyMode={env.keyMode} refMismatch={String(env.refMismatch)}
						</p>
					) : null}
					{process.env.NODE_ENV === 'production' ? null : (
						<p className="mt-2 text-xs text-amber-200/90">
							Debug endpoint:{' '}
							<Link className="underline" href="/api/admin/supabase-env-debug">
								/api/admin/supabase-env-debug
							</Link>
						</p>
					)}
				</div>
			</div>
		)
	}
	let rows: CountryRow[] = []
	let errorMessage: string | null = null
	let warningMessage: string | null = null

	try {
		const loaded = await loadCountries(supabase)
		rows = loaded.rows
		warningMessage = loaded.warning
		if (process.env.NODE_ENV !== 'production') {
			console.log('[admin/countries] Loaded countries:', rows.length)
		}
	} catch (e) {
		console.error('[admin/countries] Failed to load countries:', e)
		errorMessage = getErrorMessage(e)
		rows = []
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-lg font-semibold">Country & Feature Control</h1>
				<p className="mt-1 text-sm text-gray-400">
					Configure currency, coin rate, payouts, feature flags, and ads per country.
				</p>
				<p className="mt-3 text-xs text-gray-400">
					Uses Supabase service role (server-only) to bypass RLS.
				</p>
			</div>

			{errorMessage ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load countries: {errorMessage}
				</div>
			) : null}

			{warningMessage ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					{warningMessage}
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 overflow-auto">
				<table className="w-full min-w-[1100px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Currency</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Coin Rate</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Min Payout</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Live</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Ads</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Premium</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((c) => (
								<tr key={c.country_code}>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="font-medium">{c.country_name}</div>
										<div className="text-xs text-gray-400">{c.country_code}</div>
									</td>
									<td className="border-b border-white/10 py-3 pr-4">
										{c.currency_code ?? '—'} {c.currency_symbol ? `(${c.currency_symbol})` : ''}
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{c.coin_rate ?? '—'}</td>
									<td className="border-b border-white/10 py-3 pr-4">{c.min_payout_amount ?? '—'}</td>
									<td className="border-b border-white/10 py-3 pr-4">{formatBool(c.live_stream_enabled)}</td>
									<td className="border-b border-white/10 py-3 pr-4">{formatBool(c.ads_enabled)}</td>
									<td className="border-b border-white/10 py-3 pr-4">{formatBool(c.premium_enabled)}</td>
									<td className="border-b border-white/10 py-3 pr-4">{c.is_active ? 'Active' : 'Disabled'}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<Link
											href={`/admin/countries/${encodeURIComponent(c.country_code)}`}
											className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
										>
											Manage
										</Link>
									</td>
								</tr>
							))
						) : (
							<tr>
								<td colSpan={9} className="py-6 text-sm text-gray-400">
									No countries found (or schema not migrated yet).
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}
