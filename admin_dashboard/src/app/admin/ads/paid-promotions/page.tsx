import Link from 'next/link'
import { redirect } from 'next/navigation'

import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { logAdminAction } from '@/lib/admin/audit'
import { isPaidPromotionStatus, labelPromotionType, type PaidPromotionStatus } from '@/lib/admin/promotions'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type PaidPromoRow = {
	id: string
	user_id: string | null
	content_id: string | null
	content_type: string | null
	title: string | null
	country: string | null
	coins: number | null
	duration_days: number | null
	audience: string | null
	surface: string | null
	status: string | null
	reviewer_email: string | null
	reviewer_note: string | null
	created_at: string
}

function canManage(role: string): boolean {
	return role === 'super_admin' || role === 'operations_admin'
}

function plural(n: number, word: string) {
	return `${n} ${word}${n === 1 ? '' : 's'}`
}

function fmtDate(iso: string | null | undefined): string {
	if (!iso) return '—'
	const d = new Date(iso)
	if (Number.isNaN(d.getTime())) return String(iso)
	return d.toLocaleString()
}

function StatusPill({ status }: { status: string }) {
	const s = String(status ?? '').toLowerCase()
	const cls =
		s === 'approved' || s === 'active'
			? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
			: s === 'pending'
				? 'border-amber-500/30 bg-amber-500/10 text-amber-200'
				: s === 'rejected' || s === 'cancelled'
					? 'border-red-500/30 bg-red-500/10 text-red-200'
					: 'border-white/10 bg-white/5 text-gray-200'
	return <span className={`inline-flex rounded-full border px-2 py-1 text-xs ${cls}`}>{status}</span>
}

function Stat(props: { label: string; value: string }) {
	return (
		<div className="rounded-xl border border-white/10 bg-black/20 p-4">
			<p className="text-xs text-gray-400">{props.label}</p>
			<p className="mt-1 text-lg font-semibold text-white">{props.value}</p>
		</div>
	)
}

export default async function PaidPromotionsPage(props: {
	searchParams?: Promise<{ ok?: string; error?: string; filter?: string }>
}) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!canManage(ctx.admin.role)) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Only Ops and Super Admin can manage Paid Promotions.</p>
				<div className="mt-4">
					<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
			</div>
		)
	}

	const sp = (props.searchParams ? await props.searchParams : {}) ?? {}
	const filterStatus = sp.filter === 'approved' || sp.filter === 'rejected' ? sp.filter : 'pending'
	const country = await getAdminCountryCode()
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for Paid Promotions" />

	let rows: PaidPromoRow[] = []
	let loadError: string | null = null
	let pendingCount = 0
	let approvedCount = 0
	let rejectedCount = 0

	const [allRes, filteredRes] = await Promise.all([
		supabase
			.from('paid_promotions')
			.select('id,status', { count: 'exact' })
			.limit(500),
		supabase
			.from('paid_promotions')
			.select(
				'id,user_id,content_id,content_type,title,country,coins,duration_days,audience,surface,status,reviewer_email,reviewer_note,created_at',
			)
			.eq('status', filterStatus)
			.order('created_at', { ascending: false })
			.limit(100),
	])

	if (allRes.data) {
		const all = allRes.data as Array<{ status: string | null }>
		pendingCount = all.filter((r) => r.status === 'pending').length
		approvedCount = all.filter((r) => r.status === 'approved' || r.status === 'active').length
		rejectedCount = all.filter((r) => r.status === 'rejected' || r.status === 'cancelled').length
	}

	if (filteredRes.data && Array.isArray(filteredRes.data)) {
		rows = filteredRes.data as unknown as PaidPromoRow[]
	} else if (filteredRes.error) {
		const msg = String(filteredRes.error.message ?? '')
		const schemaMist = /paid_promotions|schema cache|could not find/i.test(msg)
		if (schemaMist) {
			loadError = 'Paid promotions table not yet in DB — run the promotion_engine migration first.'
		} else {
			loadError = msg
		}
	}

	// ── Server actions ──────────────────────────────────────────────────────
	async function reviewPaidPromotion(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!canManage(ctx.admin.role)) redirect('/admin/ads/paid-promotions?error=forbidden')

		const id = String(formData.get('id') ?? '').trim()
		const decision = String(formData.get('decision') ?? '').trim()
		const note = String(formData.get('note') ?? '').trim()
		if (!id) redirect('/admin/ads/paid-promotions?error=missing_id')
		if (decision !== 'approved' && decision !== 'rejected') redirect('/admin/ads/paid-promotions?error=invalid_decision')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/ads/paid-promotions?error=service_role_required')

		const { data: before } = await supabase
			.from('paid_promotions')
			.select('id,status,coins,country,user_id')
			.eq('id', id)
			.maybeSingle()

		if (!before) redirect('/admin/ads/paid-promotions?error=not_found')

		const nowIso = new Date().toISOString()
		const patch: Record<string, unknown> = {
			status: decision === 'approved' ? 'active' : 'rejected',
			reviewer_email: ctx.admin.email,
			reviewer_note: note || null,
			reviewed_at: nowIso,
		}
		if (decision === 'approved') {
			patch.activated_at = nowIso
		}

		const { error } = await supabase.from('paid_promotions').update(patch).eq('id', id)
		if (error) {
			redirect(`/admin/ads/paid-promotions?error=${encodeURIComponent(String(error.message ?? 'update_failed'))}`)
		}

		await logAdminAction({
			ctx,
			action: `promotions.paid.${decision}`,
			target_type: 'paid_promotion',
			target_id: id,
			before_state: before as unknown as Record<string, unknown>,
			after_state: patch,
			meta: { module: 'ads_promotions', source_type: 'paid' },
		})

		redirect('/admin/ads/paid-promotions?ok=1')
	}

	const filterTabs: Array<{ label: string; value: string; count: number }> = [
		{ label: 'Pending', value: 'pending', count: pendingCount },
		{ label: 'Approved', value: 'approved', count: approvedCount },
		{ label: 'Rejected', value: 'rejected', count: rejectedCount },
	]

	return (
		<div className="space-y-6">
			{/* Header */}
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold text-white">Paid Promotions</h1>
						<p className="mt-1 text-sm text-gray-400">
							Artists and DJs pay coins to promote their content. Review and approve/reject submissions here.
						</p>
						<p className="mt-2 text-xs text-gray-500">Country scope: {country}</p>
					</div>
					<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
			</div>

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">
					Decision saved.
				</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					{sp.error}
				</div>
			) : null}
			{loadError ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					{loadError}
				</div>
			) : null}

			{/* Stats */}
			<div className="grid gap-3 sm:grid-cols-3">
				<Stat label="Pending Review" value={String(pendingCount)} />
				<Stat label="Approved / Active" value={String(approvedCount)} />
				<Stat label="Rejected" value={String(rejectedCount)} />
			</div>

			{/* Coin-budget pricing guide */}
			<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
				<h2 className="text-sm font-semibold text-white">Coin Budget Tiers</h2>
				<div className="mt-3 overflow-x-auto">
					<table className="min-w-[480px] w-full text-sm">
						<thead className="text-xs text-gray-400">
							<tr>
								<th className="py-2 text-left">Coins</th>
								<th className="py-2 text-left">Duration</th>
								<th className="py-2 text-left">Reach</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10 text-gray-200">
							<tr>
								<td className="py-2 font-medium text-amber-300">200</td>
								<td className="py-2">1 day</td>
								<td className="py-2 text-gray-400">Small</td>
							</tr>
							<tr>
								<td className="py-2 font-medium text-amber-300">500</td>
								<td className="py-2">3 days</td>
								<td className="py-2 text-gray-300">Medium</td>
							</tr>
							<tr>
								<td className="py-2 font-medium text-amber-300">1,000</td>
								<td className="py-2">7 days</td>
								<td className="py-2 text-emerald-300">Large</td>
							</tr>
						</tbody>
					</table>
				</div>
			</div>

			{/* Filter tabs */}
			<div className="flex gap-2">
				{filterTabs.map((t) => (
					<Link
						key={t.value}
						href={`/admin/ads/paid-promotions?filter=${t.value}`}
						className={`rounded-xl border px-4 py-2 text-sm transition ${
							filterStatus === t.value
								? 'border-white bg-white text-black'
								: 'border-white/10 bg-white/5 text-gray-300 hover:bg-white/10'
						}`}
					>
						{t.label} ({t.count})
					</Link>
				))}
			</div>

			{/* Table */}
			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<div className="overflow-x-auto">
					<table className="min-w-[1000px] w-full text-sm">
						<thead className="bg-black/20 text-left text-xs text-gray-400">
							<tr>
								<th className="px-4 py-3">Creator</th>
								<th className="px-4 py-3">Content</th>
								<th className="px-4 py-3">Coins Paid</th>
								<th className="px-4 py-3">Duration</th>
								<th className="px-4 py-3">Country</th>
								<th className="px-4 py-3">Status</th>
								<th className="px-4 py-3">Submitted</th>
								{filterStatus === 'pending' ? <th className="px-4 py-3">Action</th> : null}
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10">
							{rows.length > 0 ? (
								rows.map((row) => (
									<tr key={row.id} className="hover:bg-white/5">
										<td className="px-4 py-3">
											<div className="font-medium text-white">{row.user_id ?? '—'}</div>
											<div className="mt-1 text-xs text-gray-500">Type: {labelPromotionType(row.content_type)}</div>
										</td>
										<td className="px-4 py-3">
											<div className="text-gray-200">{row.title ?? row.content_id ?? '—'}</div>
											{row.audience ? (
												<div className="mt-1 text-xs text-gray-500">Audience: {row.audience}</div>
											) : null}
											{row.surface ? (
												<div className="mt-1 text-xs text-gray-500">Surface: {row.surface}</div>
											) : null}
										</td>
										<td className="px-4 py-3 font-medium text-amber-300">
											{row.coins != null ? row.coins.toLocaleString() : '—'}
										</td>
										<td className="px-4 py-3 text-gray-200">
											{row.duration_days != null ? plural(row.duration_days, 'day') : '—'}
										</td>
										<td className="px-4 py-3 text-gray-200">{row.country ?? '—'}</td>
										<td className="px-4 py-3">
											<StatusPill status={row.status ?? 'pending'} />
											{row.reviewer_email ? (
												<div className="mt-1 text-xs text-gray-500">by {row.reviewer_email}</div>
											) : null}
											{row.reviewer_note ? (
												<div className="mt-1 text-xs text-gray-400 italic">"{row.reviewer_note}"</div>
											) : null}
										</td>
										<td className="px-4 py-3 text-xs text-gray-400">{fmtDate(row.created_at)}</td>
										{filterStatus === 'pending' ? (
											<td className="px-4 py-3">
												<div className="flex flex-col gap-2">
													<form action={reviewPaidPromotion} className="flex gap-2">
														<input type="hidden" name="id" value={row.id} />
														<input type="hidden" name="decision" value="approved" />
														<button className="h-8 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 text-xs text-emerald-200 hover:bg-emerald-500/15">
															Approve
														</button>
													</form>
													<form action={reviewPaidPromotion} className="flex gap-2">
														<input type="hidden" name="id" value={row.id} />
														<input type="hidden" name="decision" value="rejected" />
														<button className="h-8 rounded-xl border border-red-500/30 bg-red-500/10 px-3 text-xs text-red-100 hover:bg-red-500/15">
															Reject
														</button>
													</form>
												</div>
											</td>
										) : null}
									</tr>
								))
							) : (
								<tr>
									<td
										colSpan={filterStatus === 'pending' ? 8 : 7}
										className="px-4 py-8 text-center text-sm text-gray-400"
									>
										{loadError ? loadError : `No ${filterStatus} paid promotions.`}
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>

			{/* API hint for artist apps */}
			<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
				<h2 className="text-sm font-semibold text-white">Artist / DJ App Integration</h2>
				<p className="mt-2 text-sm text-gray-400">
					Creators submit paid promotion requests from the mobile app using this endpoint:
				</p>
				<pre className="mt-3 overflow-x-auto rounded-xl bg-black/40 px-4 py-3 text-xs text-gray-300">
{`POST /api/promotions/paid
Authorization: Bearer <firebase_id_token>

{
  "content_id": "<song_id or DJ id>",
  "content_type": "song | video | dj_profile | battle",
  "title": "Promote my song",
  "country": "MW",
  "coins": 500,
  "duration_days": 3,
  "audience": "all",
  "surface": "home_banner"
}`}
				</pre>
			</div>
		</div>
	)
}
