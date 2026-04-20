import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { CoinsTable, type CoinRow } from './CoinsTable'
import { getAdminContext } from '@/lib/admin/session'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

export default async function CoinsPage() {
	const ctx = await getAdminContext()
	if (!ctx || !ctx.permissions.can_manage_finance) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You do not have finance permissions.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for coins" />
	const { data, error } = await supabase
		.from('coins')
		.select('id,code,name,value_mwk,status')
		.order('value_mwk', { ascending: true })

	const coins = (data ?? []) as unknown as CoinRow[]

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Coin Types</h1>
					<p className="mt-1 text-sm text-gray-400">Enable/disable coins. No deletions.</p>
				</div>
				<Link
					href="/admin/payments"
					className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
				>
					Back to overview
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load coins: {error.message}
				</div>
			) : null}

			<CoinsTable coins={coins} />
		</div>
	)
}
