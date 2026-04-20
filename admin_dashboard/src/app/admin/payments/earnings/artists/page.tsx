import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { EarningsTable, type EarningsRow } from '../EarningsTable'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type RpcRow = {
	beneficiary_id: string
	total_coins: string | number
	earned_mwk: string | number
	withdrawn_mwk: string | number
	pending_withdrawals_mwk: string | number
	available_mwk: string | number
	status: 'active' | 'frozen'
}

export default async function ArtistEarningsPage() {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for earnings" />
	const { data: rows, error } = await supabase.rpc('finance_earnings_overview', { p_beneficiary_type: 'artist' })

	const rpcRows = ((rows ?? []) as unknown as RpcRow[]).slice(0, 500)
	const ids = rpcRows.map((r) => r.beneficiary_id)

	const namesById = new Map<string, string>()
	if (ids.length) {
		const { data: artists } = await supabase.from('artists').select('id,name,stage_name').in('id', ids)
		artists?.forEach((a: any) => {
			namesById.set(String(a.id), String(a.stage_name || a.name || 'Artist'))
		})
	}

	const tableRows: EarningsRow[] = rpcRows.map((r) => ({
		beneficiaryId: String(r.beneficiary_id),
		name: namesById.get(String(r.beneficiary_id)) ?? 'Artist',
		coins: Number(r.total_coins) || 0,
		earnedMwk: Number(r.earned_mwk) || 0,
		withdrawnMwk: Number(r.withdrawn_mwk) || 0,
		pendingWithdrawalsMwk: Number(r.pending_withdrawals_mwk) || 0,
		availableMwk: Number(r.available_mwk) || 0,
		status: r.status,
	}))

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Artist Earnings</h1>
					<p className="mt-1 text-sm text-gray-400">Totals are derived from the transactions ledger.</p>
				</div>
				<Link href="/admin/payments" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to overview
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load earnings: {error.message}. Apply finance migration in Supabase.
				</div>
			) : null}

			<EarningsTable role="artist" rows={tableRows} />
		</div>
	)
}
