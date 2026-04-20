import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { loadUserProfilesByAnyId, type UserProfileRow } from '../_profiles'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type SubRow = {
	id: number
	user_id: string
	plan_id: string
	status: string
	started_at: string
	ends_at: string | null
	auto_renew: boolean
	country_code: string
	source: string | null
	created_at: string
	subscription_plans?: { name?: string | null; price_mwk?: number | null } | null
}

function fmtDate(v: string | null): string {
	if (!v) return '—'
	try {
		return new Date(v).toLocaleString()
	} catch {
		return v
	}
}

export default async function AdminSubscriptionsConsumersPastDuePage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')
	if (!ctx.permissions.can_manage_finance) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You do not have finance permissions.</p>
				<div className="mt-4">
					<Link
						href="/admin/dashboard"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Return to dashboard
					</Link>
				</div>
			</div>
		)
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for subscriptions" />

	const now = new Date().getTime()
	const { data, error } = await supabase
		.from('user_subscriptions')
		.select('id,user_id,plan_id,status,started_at,ends_at,auto_renew,country_code,source,created_at,subscription_plans(name,price_mwk)')
		.eq('status', 'active')
		.order('created_at', { ascending: false })
		.limit(500)

	const allActive = (data ?? []) as unknown as SubRow[]
	const rows = allActive
		.filter((r) => {
			if (!r?.user_id) return false
			if (!r.ends_at) return false
			const ts = Date.parse(r.ends_at)
			if (!Number.isFinite(ts)) return false
			return ts < now
		})
		.slice(0, 200)

	const userIds = Array.from(new Set(rows.map((r) => r.user_id)))
	let profilesByUid = new Map<string, UserProfileRow>()
	try {
		profilesByUid = await loadUserProfilesByAnyId({ supabase, userIds })
	} catch {
		profilesByUid = new Map()
	}

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">Consumers — Past Due</h1>
					<p className="mt-1 text-sm text-gray-400">Subscriptions still marked active but with an end date in the past (cron may not have expired them yet).</p>
				</div>
				<Link
					href="/admin/subscriptions"
					className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
				>
					Back
				</Link>
			</div>

			{error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">Failed to load subscriptions: {error.message}</div>
			) : null}

			<div className="grid gap-4 md:grid-cols-3">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
					<div className="text-xs text-gray-400">Rows</div>
					<div className="mt-1 text-2xl font-semibold">{rows.length}</div>
				</div>
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
					<div className="text-xs text-gray-400">Unique users</div>
					<div className="mt-1 text-2xl font-semibold">{userIds.length}</div>
				</div>
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
					<div className="text-xs text-gray-400">Scan window</div>
					<div className="mt-1 text-sm text-gray-300">Latest 500 active</div>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 overflow-auto">
				<table className="w-full min-w-[1100px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">User</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Auto-renew</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Start</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">End</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Actions</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((r) => {
								const p = profilesByUid.get(r.user_id)
								const label = String(p?.username ?? p?.email ?? r.user_id)
								return (
									<tr key={r.id} className="hover:bg-white/5">
										<td className="border-b border-white/10 py-3 pr-4">
											<div className="font-medium">{label}</div>
											<div className="text-xs text-gray-500 font-mono">{r.user_id}</div>
										</td>
										<td className="border-b border-white/10 py-3 pr-4">
											<div className="font-medium">{r.subscription_plans?.name ?? r.plan_id}</div>
											<div className="text-xs text-gray-500">MWK {Number(r.subscription_plans?.price_mwk ?? 0).toLocaleString()}</div>
										</td>
										<td className="border-b border-white/10 py-3 pr-4">{r.auto_renew ? 'Yes' : 'No'}</td>
										<td className="border-b border-white/10 py-3 pr-4 text-xs">{fmtDate(r.started_at)}</td>
										<td className="border-b border-white/10 py-3 pr-4 text-xs">{fmtDate(r.ends_at)}</td>
										<td className="border-b border-white/10 py-3 pr-4">{r.country_code ?? '—'}</td>
										<td className="border-b border-white/10 py-3 pr-4">
											<Link
												href={`/admin/subscriptions/user-subscriptions?q=${encodeURIComponent(r.user_id)}`}
												className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
											>
												Manage
											</Link>
										</td>
									</tr>
								)
							})
						) : (
							<tr>
								<td colSpan={7} className="py-6 text-sm text-gray-400">
									No past-due consumer subscriptions found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>

			<div className="flex flex-wrap gap-2">
				<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back to Overview
				</Link>
				<Link href="/admin/health" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					System Health
				</Link>
			</div>
		</div>
	)
}
