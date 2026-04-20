import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'
import { trySetSubscriptionClaims } from '@/lib/subscription/firebase-claims'
import { isConsumerPlan, isArtistPlan, isDjPlan } from '@/lib/subscription/admin-plan-scope'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import SubscriptionsToolsClient from '../SubscriptionsToolsClient'

export const runtime = 'nodejs'

type SubRow = {
	id: number
	user_id: string
	plan_id: string
	status: 'active' | 'canceled' | 'expired' | 'replaced'
	started_at: string
	ends_at: string | null
	auto_renew: boolean
	country_code: string
	source: string | null
	created_at: string
	updated_at: string
	subscription_plans?: { name?: string | null; price_mwk?: number | null; audience?: string | null } | null
}

type SearchParams = { status?: string; plan?: string; q?: string; audience?: string }

type ProfileRow = {
	id: string
	display_name: string | null
	full_name: string | null
	username: string | null
	email: string | null
	role: string | null
}

function normalizeUserRole(value: unknown): 'consumer' | 'artist' | 'dj' | 'admin' | 'unknown' {
	const v = String(value ?? '').trim().toLowerCase()
	if (v === 'artist') return 'artist'
	if (v === 'dj') return 'dj'
	if (v === 'admin' || v === 'super_admin') return 'admin'
	if (v === 'user' || v === 'consumer' || v === 'listener') return 'consumer'
	return 'unknown'
}

function pickDisplayName(profile: ProfileRow | null | undefined, fallbackId: string): string {
	if (!profile) return fallbackId
	const display = String(profile.display_name ?? '').trim()
	if (display) return display
	const full = String(profile.full_name ?? '').trim()
	if (full) return full
	const user = String(profile.username ?? '').trim()
	if (user) return user
	const email = String(profile.email ?? '').trim()
	if (email) return email
	return fallbackId
}

function normalizeStatus(v: string | undefined): 'active' | 'expired' | 'canceled' | 'replaced' | 'all' {
	const s = String(v ?? 'active').trim().toLowerCase()
	if (s === 'expired') return 'expired'
	if (s === 'canceled' || s === 'cancelled') return 'canceled'
	if (s === 'replaced') return 'replaced'
	if (s === 'all') return 'all'
	return 'active'
}

function normalizePlan(v: string | undefined): 'free' | 'premium' | 'platinum' | 'all' {
	const p = String(v ?? 'all').trim().toLowerCase()
	if (p === 'free' || p === 'premium' || p === 'platinum') return p
	return 'all'
}

function normalizeAudience(v: string | undefined): 'all' | 'consumer' | 'artist' | 'dj' {
	const a = String(v ?? 'all').trim().toLowerCase()
	if (a === 'consumer') return 'consumer'
	if (a === 'artist') return 'artist'
	if (a === 'dj') return 'dj'
	return 'all'
}

function fmtDate(v: string | null): string {
	if (!v) return '—'
	try {
		return new Date(v).toLocaleString()
	} catch {
		return v
	}
}

function asClaimsStatus(value: unknown): 'active' | 'canceled' | 'expired' | 'replaced' | 'none' {
	const s = String(value ?? '').trim().toLowerCase()
	if (s === 'active' || s === 'canceled' || s === 'expired' || s === 'replaced') return s
	return 'none'
}

export default async function UserSubscriptionsAdminPage(props: { searchParams: Promise<SearchParams> }) {
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

	const sp = await props.searchParams
	const status = normalizeStatus(sp.status)
	const audience = normalizeAudience(sp.audience)
	const plan = audience === 'consumer' ? normalizePlan(sp.plan) : 'all'
	const q = String(sp.q ?? '').trim()

	async function extendSubscription(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!ctx.permissions.can_manage_finance) redirect('/admin/subscriptions/user-subscriptions?error=forbidden')

		const id = Number(formData.get('id') ?? 0)
		const months = Math.max(0, Math.min(24, Number(formData.get('months') ?? 1) || 1))
		if (!id || !Number.isFinite(id)) redirect('/admin/subscriptions/user-subscriptions?error=invalid_id')
		if (!months) redirect('/admin/subscriptions/user-subscriptions?error=invalid_months')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/subscriptions/user-subscriptions?error=service_role_required')

		const { data: before } = await supabase
			.from('user_subscriptions')
			.select('id,user_id,plan_id,status,ends_at,auto_renew')
			.eq('id', id)
			.maybeSingle()

		if (!before) redirect('/admin/subscriptions/user-subscriptions?error=not_found')

		const base = before.ends_at ? new Date(before.ends_at) : new Date()
		const next = new Date(base)
		next.setUTCMonth(next.getUTCMonth() + months)

		const { error } = await supabase
			.from('user_subscriptions')
			.update({ ends_at: next.toISOString(), updated_at: new Date().toISOString() })
			.eq('id', id)

		if (error) redirect(`/admin/subscriptions/user-subscriptions?error=${encodeURIComponent(error.message)}`)

		await logAdminAction({
			ctx,
			action: 'user_subscriptions.extend',
			target_type: 'user_subscription',
			target_id: String(id),
			before_state: before as any,
			after_state: { ...before, ends_at: next.toISOString() } as any,
			meta: { months },
		})

		await trySetSubscriptionClaims(String((before as any)?.user_id ?? ''), {
			plan_id: String((before as any)?.plan_id ?? 'free'),
			status: asClaimsStatus((before as any)?.status),
			ends_at: next.toISOString(),
		})

		redirect('/admin/subscriptions/user-subscriptions?ok=extended')
	}

	async function cancelSubscription(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!ctx.permissions.can_manage_finance) redirect('/admin/subscriptions/user-subscriptions?error=forbidden')

		const id = Number(formData.get('id') ?? 0)
		if (!id || !Number.isFinite(id)) redirect('/admin/subscriptions/user-subscriptions?error=invalid_id')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/subscriptions/user-subscriptions?error=service_role_required')

		const { data: before } = await supabase
			.from('user_subscriptions')
			.select('id,user_id,plan_id,status,ends_at,auto_renew')
			.eq('id', id)
			.maybeSingle()

		if (!before) redirect('/admin/subscriptions/user-subscriptions?error=not_found')

		const { error } = await supabase
			.from('user_subscriptions')
			.update({ status: 'canceled', auto_renew: false, updated_at: new Date().toISOString() })
			.eq('id', id)

		if (error) redirect(`/admin/subscriptions/user-subscriptions?error=${encodeURIComponent(error.message)}`)

		await logAdminAction({
			ctx,
			action: 'user_subscriptions.cancel',
			target_type: 'user_subscription',
			target_id: String(id),
			before_state: before as any,
			after_state: { ...before, status: 'canceled', auto_renew: false } as any,
			meta: {},
		})

		await trySetSubscriptionClaims(String((before as any)?.user_id ?? ''), {
			plan_id: String((before as any)?.plan_id ?? 'free'),
			status: 'canceled',
			ends_at: (before as any)?.ends_at ?? null,
		})

		redirect('/admin/subscriptions/user-subscriptions?ok=canceled')
	}

	async function refundSubscription(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!ctx.permissions.can_manage_finance) redirect('/admin/subscriptions/user-subscriptions?error=forbidden')

		const id = Number(formData.get('id') ?? 0)
		const amount = Number(formData.get('amount_mwk') ?? 0)
		if (!id || !Number.isFinite(id)) redirect('/admin/subscriptions/user-subscriptions?error=invalid_id')
		if (!Number.isFinite(amount) || amount <= 0) redirect('/admin/subscriptions/user-subscriptions?error=invalid_amount')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/subscriptions/user-subscriptions?error=service_role_required')

		const { data: before } = await supabase
			.from('user_subscriptions')
			.select('id,user_id,plan_id,status,country_code')
			.eq('id', id)
			.maybeSingle()

		if (!before) redirect('/admin/subscriptions/user-subscriptions?error=not_found')

		// Note: this is a ledger adjustment; real gateway refunds must be handled in PayChangu backend.
		const { error: txError } = await supabase.from('transactions').insert({
			type: 'adjustment',
			actor_type: 'user',
			actor_id: before.user_id,
			amount_mwk: -Math.abs(amount),
			coins: 0,
			source: 'admin_dashboard',
			country_code: before.country_code ?? 'MW',
			meta: { reason: 'subscription_refund', user_subscription_id: id, plan_id: before.plan_id },
		})

		if (txError) redirect(`/admin/subscriptions/user-subscriptions?error=${encodeURIComponent(txError.message)}`)

		await logAdminAction({
			ctx,
			action: 'user_subscriptions.refund_adjustment',
			target_type: 'user_subscription',
			target_id: String(id),
			before_state: before as any,
			after_state: null,
			meta: { amount_mwk: amount },
		})

		redirect('/admin/subscriptions/user-subscriptions?ok=refunded')
	}

	let rows: SubRow[] = []
		let loadError: string | null = null
	let profilesById: Record<string, ProfileRow> = {}
		try {
			let query = supabase
				.from('user_subscriptions')
				.select('id,user_id,plan_id,status,started_at,ends_at,auto_renew,country_code,source,created_at,updated_at,subscription_plans(name,price_mwk,audience)')
				.order('created_at', { ascending: false })
				.limit(200)
			if (status !== 'all') query = query.eq('status', status)
			if (plan !== 'all') query = query.eq('plan_id', plan)
			if (q) query = query.ilike('user_id', `%${q}%`)
			const { data, error } = await query
			if (error) {
				loadError = error.message
				rows = []
			} else {
				let out = (data ?? []) as unknown as SubRow[]
				if (audience === 'consumer') {
					out = out.filter((row) => isConsumerPlan({ plan_id: row.plan_id, audience: row.subscription_plans?.audience }))
				} else if (audience === 'artist') {
					out = out.filter((row) => isArtistPlan({ plan_id: row.plan_id, audience: row.subscription_plans?.audience }))
				} else if (audience === 'dj') {
					out = out.filter((row) => isDjPlan({ plan_id: row.plan_id, audience: row.subscription_plans?.audience }))
				}
				rows = out
			}
		} catch (e) {
			loadError = e instanceof Error ? e.message : 'Failed to load subscriptions.'
			rows = []
		}

		if (rows.length) {
			try {
				const ids = Array.from(new Set(rows.map((r) => String(r.user_id ?? '').trim()).filter(Boolean))).slice(0, 200)
				if (ids.length) {
					const { data, error } = await supabase
						.from('profiles')
						.select('id,display_name,full_name,username,email,role')
						.in('id', ids)
						.limit(500)
					if (!error && data?.length) {
						profilesById = Object.fromEntries(
							(data as unknown as ProfileRow[]).map((p) => [String(p.id), p]),
						)
					}
				}
			} catch {
				// best-effort
			}
		}

	const title = audience === 'consumer' ? 'Consumer Subscriptions' : audience === 'artist' ? 'Artist Subscriptions' : audience === 'dj' ? 'DJ Subscriptions' : 'User Subscriptions'

	return (
		<div className="space-y-6">
			<div className="flex items-center justify-between">
				<div>
					<h1 className="text-2xl font-bold">{title}</h1>
					<p className="mt-1 text-sm text-gray-400">Monitor status and manage renewals (extend/cancel/refund adjustment).</p>
				</div>
				<Link href="/admin/subscriptions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Back
				</Link>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-4">
				<form className="flex flex-wrap items-end gap-3">
					<div>
						<label className="text-xs text-gray-400">Audience</label>
						<select name="audience" defaultValue={audience} className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none">
							<option value="all">All</option>
							<option value="consumer">Consumers</option>
							<option value="artist">Artists</option>
							<option value="dj">DJs</option>
						</select>
					</div>
					<div>
						<label className="text-xs text-gray-400">Status</label>
						<select name="status" defaultValue={status} className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none">
							<option value="active">Active</option>
							<option value="expired">Expired</option>
							<option value="canceled">Canceled</option>
							<option value="replaced">Replaced</option>
							<option value="all">All</option>
						</select>
					</div>
					<div>
						<label className="text-xs text-gray-400">Plan</label>
						{audience === 'consumer' ? (
							<select name="plan" defaultValue={plan} className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none">
								<option value="all">All</option>
								<option value="free">Free</option>
								<option value="premium">Premium</option>
								<option value="platinum">Platinum</option>
							</select>
						) : (
							<select
								name="plan"
								defaultValue="all"
								disabled
								className="mt-1 h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none opacity-60"
								title="Plan filter is only available for consumer tiers"
							>
								<option value="all">All</option>
							</select>
						)}
					</div>
					<div>
						<label className="text-xs text-gray-400">User ID contains</label>
						<input name="q" defaultValue={q} className="mt-1 h-10 w-64 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none" placeholder="Firebase UID" />
					</div>
					<button type="submit" className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90">
						Filter
					</button>
				</form>
			</div>

			<SubscriptionsToolsClient initialUserId={q || undefined} />

			{loadError ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-100">
					<div className="font-semibold">Failed to load subscriptions</div>
					<div className="mt-1 break-words">{loadError}</div>
					<div className="mt-2 text-xs text-red-200/80">
						If this mentions a missing table / relationship, apply the Supabase migrations that create subscription tables and foreign keys.
					</div>
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 overflow-auto">
				<table className="w-full min-w-[1200px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">User</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Plan</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Auto-renew</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Start</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">End</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Actions</th>
						</tr>
					</thead>
					<tbody>
						{rows.length ? (
							rows.map((r) => (
								<tr key={r.id} className="hover:bg-white/5">
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="font-medium">{pickDisplayName(profilesById[r.user_id], r.user_id)}</div>
										<div className="text-xs text-gray-500">
											{normalizeUserRole(profilesById[r.user_id]?.role) !== 'unknown'
												? `${normalizeUserRole(profilesById[r.user_id]?.role)} • `
												: ''}
											{r.user_id}
										</div>
										<div className="text-xs text-gray-500">id={r.id} • src={r.source ?? '—'}</div>
									</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="font-medium">{r.subscription_plans?.name ?? r.plan_id}</div>
										<div className="text-xs text-gray-500">MWK {Number(r.subscription_plans?.price_mwk ?? 0).toLocaleString()}</div>
									</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.status}</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.auto_renew ? 'Yes' : 'No'}</td>
									<td className="border-b border-white/10 py-3 pr-4 text-xs">{fmtDate(r.started_at)}</td>
									<td className="border-b border-white/10 py-3 pr-4 text-xs">{fmtDate(r.ends_at)}</td>
									<td className="border-b border-white/10 py-3 pr-4">{r.country_code}</td>
									<td className="border-b border-white/10 py-3 pr-4">
										<div className="flex flex-wrap items-center gap-2">
											<form action={extendSubscription} className="inline-flex items-center gap-2">
												<input type="hidden" name="id" value={String(r.id)} />
												<input
													type="number"
													name="months"
													min={1}
													max={24}
													defaultValue={1}
													className="h-9 w-16 rounded-xl border border-white/10 bg-black/20 px-2 text-xs outline-none"
												/>
												<button className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">Extend</button>
											</form>

											<form action={cancelSubscription} className="inline-flex">
												<input type="hidden" name="id" value={String(r.id)} />
												<button className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">Cancel</button>
											</form>

											<form action={refundSubscription} className="inline-flex items-center gap-2">
												<input type="hidden" name="id" value={String(r.id)} />
												<input
													type="number"
													name="amount_mwk"
													min={1}
													defaultValue={0}
													className="h-9 w-24 rounded-xl border border-white/10 bg-black/20 px-2 text-xs outline-none"
													placeholder="Refund"
												/>
												<button className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">Refund</button>
											</form>

											<Link
												href={`/admin/payments/transactions?type=subscription`}
												className="h-9 inline-flex items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5"
											>
												Transactions
											</Link>
										</div>
									</td>
								</tr>
							))
						) : (
							<tr>
								<td colSpan={8} className="py-6 text-sm text-gray-400">
									No subscriptions found.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-4 text-sm text-gray-300">
				<b>Note:</b> Refund here creates a ledger adjustment only. Real PayChangu refunds should be handled in the backend gateway integration.
			</div>
		</div>
	)
}
