import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { EarningsTable, type EarningsRow } from '../EarningsTable'

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

export default async function DjEarningsPage() {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for earnings" />
	const { data: rows, error } = await supabase.rpc('finance_earnings_overview', { p_beneficiary_type: 'dj' })

	const rpcRows = ((rows ?? []) as unknown as RpcRow[]).slice(0, 500)
	const ids = rpcRows.map((r) => r.beneficiary_id)

	const namesById = new Map<string, string>()
	if (ids.length) {
		const { data: djs } = await supabase.from('djs').select('id,name,stage_name').in('id', ids)
		djs?.forEach((d: any) => {
			namesById.set(String(d.id), String(d.stage_name || d.name || 'DJ'))
		})
	}

	// Best-effort: lives hosted from live_streams.
	const livesByDjId = new Map<string, number>()
	if (ids.length) {
		const { data: lives } = await supabase
			.from('live_streams')
			.select('host_id')
			.eq('host_type', 'dj')
			.in('host_id', ids)
			.limit(10000)
		lives?.forEach((l: any) => {
			const key = String(l.host_id)
			livesByDjId.set(key, (livesByDjId.get(key) ?? 0) + 1)
		})
	}

	const tableRows: EarningsRow[] = rpcRows.map((r) => ({
		beneficiaryId: String(r.beneficiary_id),
		name: namesById.get(String(r.beneficiary_id)) ?? 'DJ',
		livesHosted: livesByDjId.get(String(r.beneficiary_id)) ?? 0,
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
					<h1 className="text-2xl font-bold">DJ Earnings</h1>
					<p className="mt-1 text-sm text-gray-400">Includes live gifts and battle rewards.</p>
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

			<EarningsTable role="dj" rows={tableRows} />
		</div>
	)
}
