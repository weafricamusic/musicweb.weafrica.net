import Link from 'next/link'

import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { loadPlatformIntelligence } from '@/lib/admin/platform-intelligence'
import { formatInt, formatMWK } from '@/app/admin/payments/_format'
import StatsCard from './StatsCard'
import ServiceRoleRequired from './ServiceRoleRequired'

export default async function AnalyticsOverview() {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for analytics" />
	const country = await getAdminCountryCode()
	const intel = await loadPlatformIntelligence({ supabase, days: 7, countryCode: country })

	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
			<div className="flex items-start justify-between gap-4">
				<div>
					<p className="text-sm font-semibold text-white">Platform Intelligence</p>
					<p className="mt-1 text-xs text-gray-400">Last 7 days{country ? ` • ${country}` : ''}</p>
				</div>
				<Link href="/admin/analytics" className="text-xs underline text-gray-200 hover:text-white">
					Open analytics
				</Link>
			</div>

			<div className="mt-4 grid grid-cols-2 gap-4">
				<StatsCard title="Revenue (MWK)" value={intel.revenueMwk7d == null ? '—' : formatMWK(intel.revenueMwk7d)} />
				<StatsCard title="Coins Sold" value={intel.coinsSold7d == null ? '—' : formatInt(intel.coinsSold7d)} />
				<StatsCard title="Open Reports" value={intel.openReports == null ? '—' : formatInt(intel.openReports)} />
				<StatsCard title="Active Streams" value={intel.activeStreams == null ? '—' : formatInt(intel.activeStreams)} />
			</div>
		</div>
	)
}
