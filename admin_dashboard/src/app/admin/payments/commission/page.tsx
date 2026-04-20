import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { formatMWK } from '../_format'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type FinanceTopSummary = {
	weafrica_commission_mwk: string | number
	commission_percent: string | number
	artist_share_percent: string | number
	dj_share_percent: string | number
}

export default async function CommissionPage() {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for commission" />
	const { data: rows, error } = await supabase.rpc('finance_top_summary')
	const summary = (Array.isArray(rows) ? rows[0] : null) as FinanceTopSummary | null

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">WeAfrica Commission</h1>
					<p className="mt-1 text-sm text-gray-400">Computed as revenue − (artist + DJ earnings).</p>
				</div>
				<Link href="/admin/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to overview
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load commission: {error.message}. Apply finance migration in Supabase.
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<p className="text-xs text-gray-400">WeAfrica Commission (all time)</p>
				<p className="mt-2 text-3xl font-semibold">{formatMWK(summary?.weafrica_commission_mwk)}</p>
				<div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">Commission %</p>
						<p className="mt-1 text-lg font-semibold">{summary?.commission_percent ?? '—'}%</p>
					</div>
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">Artist share %</p>
						<p className="mt-1 text-lg font-semibold">{summary?.artist_share_percent ?? '—'}%</p>
					</div>
					<div className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">DJ share %</p>
						<p className="mt-1 text-lg font-semibold">{summary?.dj_share_percent ?? '—'}%</p>
					</div>
				</div>
			</div>
		</div>
	)
}
