import Link from 'next/link'
import { redirect } from 'next/navigation'

import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { logAdminAction } from '@/lib/admin/audit'
import {
	isPromotionStatus,
	labelPromotionSurface,
	labelPromotionType,
	type PromotionStatus,
} from '@/lib/admin/promotions'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type AdminPromotionRow = {
	id: string
	title: string | null
	description: string | null
	promotion_type: string | null
	target_id: string | null
	country: string | null
	surface: string | null
	start_date: string | null
	end_date: string | null
	starts_at: string | null
	ends_at: string | null
	status: string | null
	created_by: string | null
	banner_url: string | null
	created_at: string
	source_type: string | null
	is_active: boolean | null
}

function canManagePromotions(role: string): boolean {
	return role === 'super_admin' || role === 'operations_admin'
}

function normalizeStatus(row: Pick<AdminPromotionRow, 'status' | 'is_active'>): PromotionStatus {
	if (isPromotionStatus(row.status)) return row.status
	if (row.is_active) return 'active'
	return 'draft'
}

function fmtDate(iso: string | null | undefined): string {
	if (!iso) return '—'
	const d = new Date(iso)
	if (Number.isNaN(d.getTime())) return String(iso)
	return d.toLocaleString()
}

function Stat(props: { label: string; value: string }) {
	return (
		<div className="rounded-xl border border-white/10 bg-black/20 p-4">
			<p className="text-xs text-gray-400">{props.label}</p>
			<p className="mt-1 text-lg font-semibold text-white">{props.value}</p>
		</div>
	)
}

function StatusPill({ status }: { status: PromotionStatus }) {
	const cls =
		status === 'active'
			? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
			: status === 'scheduled'
				? 'border-blue-500/30 bg-blue-500/10 text-blue-200'
				: status === 'paused'
					? 'border-amber-500/30 bg-amber-500/10 text-amber-200'
					: status === 'ended' || status === 'rejected'
						? 'border-red-500/30 bg-red-500/10 text-red-200'
						: 'border-white/10 bg-white/5 text-gray-200'
	
	return <span className={`inline-flex rounded-full border px-2 py-1 text-xs ${cls}`}>{status}</span>
}

export default async function AdminPromotionsPage(props: {
	searchParams?: Promise<{ ok?: string; error?: string }>
}) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!canManagePromotions(ctx.admin.role)) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Only Ops and Super Admin can manage Admin Promotions.</p>
				<div className="mt-4">
					<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back to Ads & Promotions
					</Link>
				</div>
			</div>
		)
	}

	const sp = (props.searchParams ? await props.searchParams : {}) ?? {}
	const country = await getAdminCountryCode()
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for Admin Promotions" />

	let rows: AdminPromotionRow[] = []
	let loadError: string | null = null

	const primary = await supabase
		.from('promotions')
		.select('id,title,description,promotion_type,target_id,country,surface,start_date,end_date,starts_at,ends_at,status,created_by,banner_url,created_at,source_type,is_active')
		.eq('source_type', 'admin')
		.order('created_at', { ascending: false })
		.limit(250)

	if (primary.data && Array.isArray(primary.data)) {
		rows = primary.data as unknown as AdminPromotionRow[]
	} else {
		const msg = String(primary.error?.message ?? '')
		const schemaMismatch = /source_type|promotion_type|start_date|end_date|schema cache|could not find/i.test(msg)

		if (schemaMismatch) {
			const fallback = await supabase
				.from('promotions')
				.select('id,title,description,created_at,is_active')
				.order('created_at', { ascending: false })
				.limit(250)

			if (fallback.data && Array.isArray(fallback.data)) {
				rows = (fallback.data as Array<Record<string, unknown>>).map((r) => ({
					id: String(r.id ?? ''),
					title: typeof r.title === 'string' ? r.title : null,
					description: typeof r.description === 'string' ? r.description : null,
					promotion_type: null,
					target_id: null,
					country,
					surface: null,
					start_date: null,
					end_date: null,
					starts_at: null,
					ends_at: null,
					status: null,
					created_by: null,
					banner_url: null,
					created_at: String(r.created_at ?? ''),
					source_type: 'admin',
					is_active: Boolean(r.is_active),
				}))
			} else {
				loadError = String(fallback.error?.message ?? 'Failed to load promotions')
			}
		} else {
			loadError = String(primary.error?.message ?? 'Failed to load promotions')
		}
	}

	const adminRows = rows.filter((r) => !r.source_type || r.source_type === 'admin')
	const statusCounts = adminRows.reduce(
		(acc, row) => {
			const status = normalizeStatus(row)
			acc.all += 1
			acc[status] += 1
			return acc
		},
		{ all: 0, draft: 0, scheduled: 0, active: 0, paused: 0, ended: 0, rejected: 0 } satisfies Record<string, number>,
	)

	async function setPromotionStatus(formData: FormData) {
		'use server'

		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!canManagePromotions(ctx.admin.role)) redirect('/admin/ads/admin-promotions?error=forbidden')

		const id = String(formData.get('id') ?? '').trim()
		const nextRaw = String(formData.get('status') ?? '').trim()
		if (!id) redirect('/admin/ads/admin-promotions?error=missing_id')
		if (!isPromotionStatus(nextRaw)) redirect('/admin/ads/admin-promotions?error=invalid_status')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/ads/admin-promotions?error=service_role_required')

		const { data: before } = await supabase
			.from('promotions')
			.select('id,status,is_active,start_date,end_date,starts_at,ends_at')
			.eq('id', id)
			.maybeSingle()

		if (!before) redirect('/admin/ads/admin-promotions?error=not_found')

		const nowIso = new Date().toISOString()
		const patch: Record<string, unknown> = {
			status: nextRaw,
			is_active: nextRaw === 'active',
		}
		const beforeMap = (before ?? {}) as Record<string, unknown>

		if (nextRaw === 'active' && !beforeMap.start_date && !beforeMap.starts_at) {
			patch.start_date = nowIso
			patch.starts_at = nowIso
		}
		if (nextRaw === 'ended') {
			patch.end_date = nowIso
			patch.ends_at = nowIso
			patch.is_active = false
		}

		let { error } = await supabase.from('promotions').update(patch).eq('id', id)
		if (error) {
			const msg = String(error.message ?? '').toLowerCase()
			const dateColsMissing = msg.includes('start_date') || msg.includes('end_date') || msg.includes('starts_at') || msg.includes('ends_at')
			if (dateColsMissing) {
				const patchFallback = {
					status: nextRaw,
					is_active: nextRaw === 'active',
				}
				;({ error } = await supabase.from('promotions').update(patchFallback).eq('id', id))
			}
		}
		if (error) {
			redirect(`/admin/ads/admin-promotions?error=${encodeURIComponent(String(error.message ?? 'update_failed'))}`)
		}

		await logAdminAction({
			ctx,
			action: 'promotions.admin.set_status',
			target_type: 'promotion',
			target_id: id,
			before_state: before as unknown as Record<string, unknown>,
			after_state: patch,
			meta: { module: 'ads_promotions', source_type: 'admin' },
		})

		redirect('/admin/ads/admin-promotions?ok=1')
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Admin Promotions</h1>
						<p className="mt-1 text-sm text-gray-400">Admin-controlled placements for artists, DJs, battles, events, and ride promotions.</p>
						<p className="mt-3 text-xs text-gray-500">Country scope: {country}</p>
					</div>
					<div className="flex flex-wrap gap-2">
						<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Back
						</Link>
						<Link href="/admin/ads/admin-promotions/new" className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90">
							+ Create Promotion
						</Link>
					</div>
				</div>
			</div>

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved.</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{sp.error}</div>
			) : null}
			{loadError ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					{loadError}
				</div>
			) : null}

			<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7">
				<Stat label="All" value={String(statusCounts.all)} />
				<Stat label="Draft" value={String(statusCounts.draft)} />
				<Stat label="Scheduled" value={String(statusCounts.scheduled)} />
				<Stat label="Active" value={String(statusCounts.active)} />
				<Stat label="Paused" value={String(statusCounts.paused)} />
				<Stat label="Ended" value={String(statusCounts.ended)} />
				<Stat label="Rejected" value={String(statusCounts.rejected)} />
			</div>

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<div className="overflow-x-auto">
					<table className="min-w-[980px] w-full text-sm">
						<thead className="bg-black/20 text-left text-xs text-gray-400">
							<tr>
								<th className="px-4 py-3">Promotion</th>
								<th className="px-4 py-3">Type</th>
								<th className="px-4 py-3">Country</th>
								<th className="px-4 py-3">Surface</th>
								<th className="px-4 py-3">Schedule</th>
								<th className="px-4 py-3">Status</th>
								<th className="px-4 py-3 text-right">Actions</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10">
							{adminRows.length ? (
								adminRows.map((row) => {
									const status = normalizeStatus(row)
									const start = row.start_date ?? row.starts_at
									const end = row.end_date ?? row.ends_at
									return (
										<tr key={row.id} className="hover:bg-white/5">
											<td className="px-4 py-3">
												<div className="font-medium text-white">{row.title ?? 'Untitled Promotion'}</div>
												<div className="mt-1 text-xs text-gray-400">Target: {row.target_id ?? '—'}</div>
												<div className="mt-1 text-xs text-gray-500">Created: {fmtDate(row.created_at)}</div>
											</td>
											<td className="px-4 py-3 text-gray-200">{labelPromotionType(row.promotion_type)}</td>
											<td className="px-4 py-3 text-gray-200">{row.country ?? 'MW'}</td>
											<td className="px-4 py-3 text-gray-200">{labelPromotionSurface(row.surface)}</td>
											<td className="px-4 py-3 text-xs text-gray-300">
												<div>Start: {fmtDate(start)}</div>
												<div>End: {fmtDate(end)}</div>
											</td>
											<td className="px-4 py-3">
												<StatusPill status={status} />
											</td>
											<td className="px-4 py-3">
												<div className="flex flex-wrap justify-end gap-2">
													<form action={setPromotionStatus}>
														<input type="hidden" name="id" value={row.id} />
														<input type="hidden" name="status" value="active" />
														<button className="h-9 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 text-xs text-emerald-200 hover:bg-emerald-500/15">
															Activate
														</button>
													</form>
													<form action={setPromotionStatus}>
														<input type="hidden" name="id" value={row.id} />
														<input type="hidden" name="status" value="paused" />
														<button className="h-9 rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 text-xs text-amber-100 hover:bg-amber-500/15">
															Pause
														</button>
													</form>
													<form action={setPromotionStatus}>
														<input type="hidden" name="id" value={row.id} />
														<input type="hidden" name="status" value="ended" />
														<button className="h-9 rounded-xl border border-red-500/30 bg-red-500/10 px-3 text-xs text-red-100 hover:bg-red-500/15">
															End
														</button>
													</form>
												</div>
											</td>
										</tr>
									)
								})
							) : (
								<tr>
									<td className="px-4 py-6 text-sm text-gray-400" colSpan={7}>
										No admin promotions yet. Create your first campaign.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>
		</div>
	)
}
