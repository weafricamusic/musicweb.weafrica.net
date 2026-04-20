import Link from 'next/link'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type PaymentRow = {
	id: string
	provider: string
	provider_reference: string
	event_type: string | null
	status: string
	user_id: string | null
	plan_id: string | null
	amount_mwk: number
	currency: string | null
	country_code: string | null
	created_at: string
	updated_at: string
}

export default async function SubscriptionPaymentsAdminPage() {
	const ctx = await getAdminContext()
	if (!ctx || !ctx.permissions.can_manage_finance) {
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
	if (!supabase) return <ServiceRoleRequired title="Service role required for subscription payments" />

	const { data, error } = await supabase
		.from('subscription_payments')
		.select('id,provider,provider_reference,event_type,status,user_id,plan_id,amount_mwk,currency,country_code,created_at,updated_at')
		.order('created_at', { ascending: false })
		.limit(100)

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Subscription payments</h1>
					<p className="mt-1 text-sm text-gray-400">Webhook-ingested PayChangu payment events (latest 100).</p>
				</div>
				<Link href="/admin/subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to subscriptions
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					Failed to load subscription payments: {error.message}. Apply the PayChangu subscriptions migration in Supabase.
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="mt-4 overflow-auto">
					<table className="w-full min-w-[1100px] border-separate border-spacing-0 text-left text-sm">
						<thead>
							<tr className="text-gray-400">
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Time</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Provider</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Reference</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Event</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">User</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Amount</th>
								<th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
							</tr>
						</thead>
						<tbody>
							{((data ?? []) as PaymentRow[]).length ? (
								((data ?? []) as PaymentRow[]).map((p) => (
									<tr key={p.id} className="hover:bg-white/5">
										<td className="border-b border-white/10 py-3 pr-4 text-xs text-gray-300">{new Date(p.created_at).toLocaleString()}</td>
										<td className="border-b border-white/10 py-3 pr-4">{p.provider}</td>
										<td className="border-b border-white/10 py-3 pr-4 font-mono text-xs">{p.provider_reference}</td>
										<td className="border-b border-white/10 py-3 pr-4">{p.event_type ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											{p.status === 'paid' ? (
												<span className="rounded-full bg-emerald-500/10 px-2 py-1 text-xs text-emerald-300">Paid</span>
											) : p.status === 'pending' ? (
												<span className="rounded-full bg-white/5 px-2 py-1 text-xs text-gray-300">Pending</span>
											) : (
												<span className="rounded-full bg-red-500/10 px-2 py-1 text-xs text-red-200">{p.status}</span>
											)}
										</td>
										<td className="border-b border-white/10 py-3 pr-4 font-mono text-xs">{p.user_id ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">{p.plan_id ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">{Number(p.amount_mwk ?? 0).toLocaleString()} {p.currency ?? ''}</td>
										<td className="border-b border-white/10 py-3 pr-4">{p.country_code ?? '—'}</td>
									</tr>
								))
							) : (
								<tr>
									<td colSpan={9} className="py-6 text-sm text-gray-400">
										No payment events yet. Ensure the webhook is configured and the migration is applied.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 text-sm text-gray-300">
				<b>Webhook endpoint:</b> <span className="font-mono">POST /api/webhooks/paychangu</span>
				<br />
				<b>Cron endpoint:</b> <span className="font-mono">POST /api/cron/subscriptions/expire</span>
			</div>
		</div>
	)
}
