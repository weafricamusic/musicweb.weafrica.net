import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import CountrySelector from './CountrySelector'
import { getAdminContext } from '@/lib/admin/session'
import { LogoutButton } from '@/components/LogoutButton'
import { getPendingApprovalsCount } from '@/lib/admin/pendingApprovals'

export default async function TopBar() {
	const supabase = tryCreateSupabaseAdminClient()
	const currentCode = await getAdminCountryCode()
	const ctx = await getAdminContext()
	const pendingApprovals = supabase ? await getPendingApprovalsCount(supabase) : null
	let countries: { country_code: string; country_name: string }[] = [{ country_code: 'MW', country_name: 'Malawi' }]
	if (supabase) {
		const primary = await supabase
			.from('countries')
			.select('country_code,country_name')
			.eq('is_active', true)
			.order('country_name', { ascending: true })
		if (primary.data && Array.isArray(primary.data) && primary.data.length) {
			countries = primary.data as { country_code: string; country_name: string }[]
		} else if (primary.error?.code === '42703') {
			// Legacy schema fallback: `code` + `name`
			const legacy = await supabase
				.from('countries')
				.select('code,name')
				.order('name', { ascending: true })
			if (legacy.data && Array.isArray(legacy.data) && legacy.data.length) {
				countries = (legacy.data as unknown[])
					.map((row) => {
						const r = (row ?? {}) as Record<string, unknown>
						return {
							country_code: String(r.code ?? '').trim().toUpperCase(),
							country_name: String(r.name ?? '').trim(),
						}
					})
					.filter((r) => r.country_code && r.country_name)
			}
		}
	}

	return (
		<header className="h-16 border-b border-zinc-800 px-4 md:px-6 flex items-center justify-between bg-zinc-950">
			<div className="flex gap-4 items-center">
				<label
					htmlFor="admin-nav"
					className="md:hidden inline-flex h-9 w-9 items-center justify-center rounded-lg border border-zinc-800 bg-zinc-900 hover:bg-zinc-800"
					aria-label="Open navigation"
				>
					☰
				</label>
				<CountrySelector countries={countries} current={currentCode} />
				<div className="hidden sm:flex gap-4">
					<Stat label="Active Streams" value="—" />
					<Stat label="Pending Approvals" value={pendingApprovals == null ? '—' : pendingApprovals.toLocaleString()} />
					<Stat label="Coins Balance" value="—" />
				</div>
			</div>

				<div className="flex items-center gap-3">
					<div className="text-right">
						<div className="text-sm font-semibold">{ctx?.admin.email ?? '—'}</div>
						<div className="text-xs text-gray-400">{ctx?.admin.role ?? '—'}</div>
					</div>
					<LogoutButton />
				</div>
		</header>
	)
}

function Stat({ label, value }: { label: string; value: string }) {
	return (
		<div className="bg-white/5 px-4 py-2 rounded-lg">
			<p className="text-xs text-gray-400">{label}</p>
			<p className="font-semibold">{value}</p>
		</div>
	)
}
