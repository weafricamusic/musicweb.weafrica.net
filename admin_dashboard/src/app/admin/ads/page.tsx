import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode, getCountryConfigByCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type CountryAdsRow = {
	country_code: string
	country_name: string
	ads_enabled: boolean | null
	is_active: boolean | null
}

export default async function AdsPage(props: { searchParams?: Promise<{ ok?: string; error?: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const isOps = ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin'
	if (!isOps) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Only Ops and Super Admin can manage ads & promotions.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}

	const sp = (props.searchParams ? await props.searchParams : {}) ?? {}
	const currentCountry = await getAdminCountryCode()
	const currentConfig = await getCountryConfigByCode(currentCountry)

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return (
			<div className="space-y-6">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Advertisements & Promotions</h1>
					<p className="mt-1 text-sm text-gray-400">Enable/disable ads per country and manage promotion surfaces.</p>
				</div>
				<ServiceRoleRequired title="Service role required for ads settings" />
			</div>
		)
	}
	let rows: CountryAdsRow[] = []
	const primary = await supabase
		.from('countries')
		.select('country_code,country_name,ads_enabled,is_active')
		.order('country_name', { ascending: true })
		.limit(250)
	if (primary.data && Array.isArray(primary.data)) {
		rows = primary.data as unknown as CountryAdsRow[]
	} else if (primary.error?.code === '42703' || String(primary.error?.message ?? '').toLowerCase().includes('country_code')) {
		// Legacy schema fallback: `code` + `name`
		const legacy = await supabase
			.from('countries')
			.select('code,name,ads_enabled,is_active')
			.order('name', { ascending: true })
			.limit(250)
		rows = (legacy.data && Array.isArray(legacy.data)
			? (legacy.data as unknown[])
				.map((row) => {
					const r = (row ?? {}) as Record<string, unknown>
					return {
						country_code: String(r.code ?? '').trim().toUpperCase(),
						country_name: String(r.name ?? '').trim(),
						ads_enabled: (r.ads_enabled as boolean | null | undefined) ?? null,
						is_active: (r.is_active as boolean | null | undefined) ?? null,
					} satisfies CountryAdsRow
				})
				.filter((r) => r.country_code && r.country_name)
			: []) as CountryAdsRow[]
	}

	async function setCountryAds(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const isOps = ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin'
		if (!isOps) redirect('/admin/ads?error=forbidden')

		const code = String(formData.get('country_code') ?? '').trim().toUpperCase()
		const enabled = String(formData.get('ads_enabled') ?? '').trim()
		if (!/^[A-Z]{2}$/.test(code)) redirect('/admin/ads?error=invalid_country')
		if (!(enabled === 'true' || enabled === 'false')) redirect('/admin/ads?error=invalid_value')

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/ads?error=service_role_required')

		let before: Record<string, unknown> | null = null
		try {
			let data: any = null
			let error: any = null
			;({ data, error } = await supabaseAdmin
				.from('countries')
				.select('ads_enabled')
				.eq('country_code', code)
				.limit(1)
				.maybeSingle())
			const msg = String(error?.message ?? '').toLowerCase()
			const missingCountryCode = String(error?.code ?? '') === '42703' || msg.includes('country_code')
			if (error && missingCountryCode) {
				;({ data, error } = await supabaseAdmin
					.from('countries')
					.select('ads_enabled')
					.eq('code', code)
					.limit(1)
					.maybeSingle())
			}
			if (error) throw error
			before = (data ?? null) as unknown as Record<string, unknown> | null
		} catch {
			before = null
		}

		try {
			const nextVal = enabled === 'true'
			let error: any = null
			;({ error } = await supabaseAdmin.from('countries').update({ ads_enabled: nextVal }).eq('country_code', code))
			const msg = String(error?.message ?? '').toLowerCase()
			const missingCountryCode = String(error?.code ?? '') === '42703' || msg.includes('country_code')
			if (error && missingCountryCode) {
				;({ error } = await supabaseAdmin.from('countries').update({ ads_enabled: nextVal }).eq('code', code))
			}
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'ads.toggle',
				target_type: 'country',
				target_id: code,
				before_state: before,
				after_state: { ads_enabled: nextVal },
				meta: { module: 'ads_promotions' },
			})

			redirect('/admin/ads?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'update_failed'
			redirect(`/admin/ads?error=${encodeURIComponent(msg)}`)
		}
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Advertisements & Promotions</h1>
						<p className="mt-1 text-sm text-gray-400">Country-aware promotion operations for admin campaigns and paid creator boosts.</p>
						<p className="mt-3 text-xs text-gray-400">Selected country: {currentCountry}</p>
						<p className="mt-2 text-xs text-gray-500">
							Consumer preview:{' '}
							<a
								className="underline hover:text-gray-300"
								href={`/api/ads/config?country_code=${encodeURIComponent(currentCountry)}&plan_id=free`}
								target="_blank"
								rel="noreferrer"
							>
								free
							</a>
							{' '}•{' '}
							<a
								className="underline hover:text-gray-300"
								href={`/api/ads/config?country_code=${encodeURIComponent(currentCountry)}&plan_id=premium`}
								target="_blank"
								rel="noreferrer"
							>
								premium
							</a>
							{' '}•{' '}
							<a
								className="underline hover:text-gray-300"
								href={`/api/ads/config?country_code=${encodeURIComponent(currentCountry)}&plan_id=platinum`}
								target="_blank"
								rel="noreferrer"
							>
								platinum
							</a>
						</p>
					</div>
					<div className="flex flex-wrap gap-2">
						<Link href="/admin/ads/admin-promotions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Admin Promotions
						</Link>
						<Link href="/admin/ads/paid-promotions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Paid Promotions
						</Link>
						<Link href="/admin/ads/campaigns" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Campaigns
						</Link>
						<Link href="/admin/ads/surfaces" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Surfaces
						</Link>
						<Link href="/admin/ads/analytics" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Analytics
						</Link>
						<Link href={`/admin/countries/${encodeURIComponent(currentCountry)}`} className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Country settings
						</Link>
					</div>
				</div>
			</div>

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved.</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{sp.error}</div>
			) : null}

			<div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
				<ModuleCard
					title="Country Settings"
					description="Enable/disable ads and local market controls."
					href={`/admin/countries/${encodeURIComponent(currentCountry)}`}
				/>
				<ModuleCard
					title="Ad Campaigns"
					description="Direct brand campaigns and scheduling controls."
					href="/admin/ads/campaigns"
				/>
				<ModuleCard
					title="Admin Promotions"
					description="Promote artists, DJs, battles, events, and rides."
					href="/admin/ads/admin-promotions"
				/>
				<ModuleCard
					title="Paid Promotions"
					description="Review creator-paid promotion requests and approvals."
					href="/admin/ads/paid-promotions"
				/>
				<ModuleCard
					title="Promotion Surfaces"
					description="Home Banner, Discover, Feed, Live Battle, and Events."
					href="/admin/ads/surfaces"
				/>
				<ModuleCard
					title="Analytics"
					description="Views, clicks, engagement, and country trending."
					href="/admin/ads/analytics"
				/>
			</div>

			<div className="grid gap-4 md:grid-cols-2">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Current Country (Quick View)</h2>
					<div className="mt-4 space-y-2 text-sm">
						<Row label="Ads Enabled" value={currentConfig ? (currentConfig.ads_enabled ? 'Yes' : 'No') : '—'} />
						<Row label="Country Active" value={currentConfig ? (currentConfig.is_active ? 'Yes' : 'No') : '—'} />
						<Row label="Ad Frequency" value="Configurable (UI stub)" />
						<Row label="Direct Brand Ads" value="Campaigns (UI stub)" />
						<Row label="In-app Promotions" value="Campaigns (UI stub)" />
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Promotion Surfaces</h2>
					<p className="mt-1 text-sm text-gray-400">Ready for: Promote Artists, DJs, Battles, WeAfrica Ride.</p>
					<div className="mt-4 grid gap-3">
						<Link href="/admin/artists" className="rounded-xl border border-white/10 bg-black/20 p-4 hover:bg-white/5">
							<p className="text-sm font-semibold">Promote Artists</p>
							<p className="mt-1 text-xs text-gray-400">Select top artists by country</p>
						</Link>
						<Link href="/admin/djs" className="rounded-xl border border-white/10 bg-black/20 p-4 hover:bg-white/5">
							<p className="text-sm font-semibold">Promote DJs</p>
							<p className="mt-1 text-xs text-gray-400">Boost verified DJs</p>
						</Link>
						<Link href="/admin/live-streams" className="rounded-xl border border-white/10 bg-black/20 p-4 hover:bg-white/5">
							<p className="text-sm font-semibold">Promote Battles</p>
							<p className="mt-1 text-xs text-gray-400">Highlight safe live streams</p>
						</Link>
					</div>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 overflow-auto">
				<div className="flex items-center justify-between gap-4">
					<div>
						<h2 className="text-base font-semibold">Ads by Country</h2>
						<p className="mt-1 text-sm text-gray-400">One switch per market. (Africa is not one market.)</p>
					</div>
					{!tryCreateSupabaseAdminClient() ? (
						<div className="text-xs text-amber-200">Set service role for changes (RLS).</div>
					) : null}
				</div>

				<table className="mt-4 w-full min-w-[900px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Ads</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((r) => (
								<tr key={r.country_code}>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="font-medium">{r.country_name}</div>
										<div className="text-xs text-gray-400">{r.country_code}</div>
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.ads_enabled ? 'Enabled' : 'Disabled'}</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.is_active ? 'Active' : 'Disabled'}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<form action={setCountryAds} className="inline-flex items-center gap-2">
											<input type="hidden" name="country_code" value={r.country_code} />
											<input type="hidden" name="ads_enabled" value={r.ads_enabled ? 'false' : 'true'} />
											<button
												disabled={!tryCreateSupabaseAdminClient()}
												className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5 disabled:opacity-60"
											>
												{r.ads_enabled ? 'Disable ads' : 'Enable ads'}
											</button>
										</form>
										<Link
											href={`/admin/countries/${encodeURIComponent(r.country_code)}`}
											className="ml-2 inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
										>
											Edit
										</Link>
									</td>
								</tr>
							))
						) : (
							<tr>
								<td colSpan={4} className="py-6 text-sm text-gray-400">No countries loaded yet.</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}

function ModuleCard(props: { title: string; description: string; href: string }) {
	return (
		<Link href={props.href} className="rounded-2xl border border-white/10 bg-white/5 p-5 transition hover:bg-white/10">
			<p className="text-sm font-semibold text-white">{props.title}</p>
			<p className="mt-1 text-xs text-gray-400">{props.description}</p>
			<p className="mt-3 text-xs text-gray-500">Open module →</p>
		</Link>
	)
}

function Row(props: { label: string; value: string }) {
	return (
		<div className="flex items-center justify-between gap-4">
			<span className="text-gray-400">{props.label}</span>
			<span className="font-medium">{props.value}</span>
		</div>
	)
}
