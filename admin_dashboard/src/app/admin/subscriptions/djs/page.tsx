import Link from 'next/link'
import { redirect } from 'next/navigation'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { isDjPlan } from '@/lib/subscription/admin-plan-scope'
import SubscriptionsToolsClient from '../SubscriptionsToolsClient'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type PlanRow = {
	plan_id: string
	audience?: string | null
	name: string
	price_mwk: number
	billing_interval: string
	is_active?: boolean | null
}

type PlanCountRow = { plan_id: string; active_count: string | number }

export default async function AdminSubscriptionsDJsPage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')
	if (!ctx.permissions.can_manage_finance) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You do not have finance permissions.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Return to dashboard
					</Link>
				</div>
			</div>
		)
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for subscriptions" />

	let plans: any[] | null = null
	let plansError: any = null
	;({ data: plans, error: plansError } = await supabase
		.from('subscription_plans')
		.select('audience,plan_id,name,price_mwk,billing_interval,is_active')
		.order('price_mwk', { ascending: true }))

	if (plansError && String(plansError.message ?? '').includes('column subscription_plans.audience does not exist')) {
		;({ data: plans, error: plansError } = await supabase
			.from('subscription_plans')
			.select('plan_id,name,price_mwk,billing_interval,is_active')
			.order('price_mwk', { ascending: true }))
	}

	const { data: planCounts } = await supabase.rpc('subscription_plan_counts', { p_country_code: null })
	const djPlans = ((plans ?? []) as PlanRow[]).filter((p) => isDjPlan(p))
	const countsByPlan = new Map<string, number>(((planCounts ?? []) as PlanCountRow[]).map((r) => [String(r.plan_id), Number(r.active_count ?? 0)]))

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">DJ Subscriptions</h1>
					<p className="mt-1 text-sm text-gray-400">Manage DJ subscription plans and assignments.</p>
				</div>
				<div className="flex flex-wrap gap-2">
					<Link href="/admin/subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Back</Link>
					<Link href="/admin/subscriptions/user-subscriptions?audience=dj" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">User subs</Link>
				</div>
			</div>

			{plansError ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load subscription plans: {plansError.message}. Apply the subscriptions migration in Supabase.
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Plan catalog</h2>
				<div className="mt-4 overflow-auto">
					<table className="w-full min-w-[860px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Price (MWK)</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Duration</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Active subs</th>
							</tr>
						</thead>
						<tbody>
							{djPlans.length ? (
								djPlans.map((p) => (
									<tr key={p.plan_id} className="hover:bg-white/5">
										<td className="border-b border-white/10 py-3 pr-4 font-medium">{p.name}</td>
										<td className="border-b border-white/10 py-3 pr-4">{Number(p.price_mwk ?? 0).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{String(p.billing_interval ?? 'month')}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{p.is_active === false ? (
												<span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Inactive</span>
											) : (
												<span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Active</span>
											)}
										</td>
										<td className="border-b border-white/10 py-3 pr-4">{countsByPlan.get(p.plan_id) ?? 0}</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={5} className="py-6 text-sm text-gray-400">No DJ plans found.</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>

			<SubscriptionsToolsClient audience="dj" />
		</div>
	)
}
