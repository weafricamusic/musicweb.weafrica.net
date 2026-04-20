import Link from 'next/link'
import { redirect } from 'next/navigation'

import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { logAdminAction } from '@/lib/admin/audit'
import {
	AD_CAMPAIGN_APPROVAL_STATUSES,
	AD_CAMPAIGN_FORMATS,
	AD_CAMPAIGN_STATUSES,
	AD_CAMPAIGN_SURFACES,
	AD_CAMPAIGN_TYPES,
	isAdCampaignApprovalStatus,
	isAdCampaignFormat,
	isAdCampaignStatus,
	isAdCampaignSurface,
	isAdCampaignType,
	labelAdCampaignApprovalStatus,
	labelAdCampaignFormat,
	labelAdCampaignStatus,
	labelAdCampaignSurface,
	labelAdCampaignType,
	normalizeCountryCode,
	toIsoOrNull,
} from '@/lib/admin/promotions'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode, getCountryConfigByCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type SearchParams = {
	ok?: string
	error?: string
	edit?: string
}

type AdCampaignRow = {
	id: string
	country_code: string
	campaign_type: string
	format: string
	surface: string
	title: string
	description: string | null
	sponsor_name: string | null
	asset_url: string | null
	video_url: string | null
	cta_label: string | null
	cta_url: string | null
	audience: string | null
	target_type: string | null
	target_ref_id: string | null
	starts_at: string | null
	ends_at: string | null
	frequency_cap_daily: number
	priority: number
	status: string
	approval_status: string
	is_enabled: boolean
	created_by: string | null
	approved_by: string | null
	approved_at: string | null
	rejection_reason: string | null
	metadata: unknown
	created_at: string
	updated_at: string
}

function canManage(role: string): boolean {
	return role === 'super_admin' || role === 'operations_admin'
}

function fmtDate(iso: string | null | undefined): string {
	if (!iso) return '—'
	const d = new Date(iso)
	if (Number.isNaN(d.getTime())) return String(iso)
	return d.toLocaleString()
}

function isLiveNow(row: Pick<AdCampaignRow, 'starts_at' | 'ends_at' | 'approval_status' | 'status' | 'is_enabled'>): boolean {
	if (!row.is_enabled) return false
	if (row.approval_status !== 'approved') return false
	if (!(row.status === 'scheduled' || row.status === 'active')) return false
	const now = Date.now()
	const startsAt = row.starts_at ? new Date(row.starts_at).getTime() : null
	const endsAt = row.ends_at ? new Date(row.ends_at).getTime() : null
	if (startsAt != null && Number.isFinite(startsAt) && startsAt > now) return false
	if (endsAt != null && Number.isFinite(endsAt) && endsAt <= now) return false
	return true
}

function parseNonNegativeInt(raw: unknown, fallback = 0): number {
	const value = Number(raw)
	if (!Number.isFinite(value)) return fallback
	return Math.max(0, Math.trunc(value))
}

function parseMetadata(input: string): { ok: true; value: Record<string, unknown> } | { ok: false; error: string } {
	if (!input.trim()) return { ok: true, value: {} }
	try {
		const parsed = JSON.parse(input)
		if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
			return { ok: false, error: 'metadata_must_be_object' }
		}
		return { ok: true, value: parsed as Record<string, unknown> }
	} catch {
		return { ok: false, error: 'invalid_metadata_json' }
	}
}

function toDateTimeLocalValue(iso: string | null | undefined): string {
	if (!iso) return ''
	const date = new Date(iso)
	if (Number.isNaN(date.getTime())) return ''
	return new Date(date.getTime() - date.getTimezoneOffset() * 60 * 1000).toISOString().slice(0, 16)
}

function buildCampaignPatch(formData: FormData, fallbackCountry: string) {
	const title = String(formData.get('title') ?? '').trim()
	const campaignType = String(formData.get('campaign_type') ?? '').trim()
	const format = String(formData.get('format') ?? '').trim()
	const surface = String(formData.get('surface') ?? '').trim()
	const countryCode = normalizeCountryCode(formData.get('country_code'), fallbackCountry)
	const requestedStatus = String(formData.get('status') ?? '').trim()
	const requestedApproval = String(formData.get('approval_status') ?? '').trim()
	const requestedEnabled = String(formData.get('is_enabled') ?? '').trim() === 'true'
	const startsAt = toIsoOrNull(formData.get('starts_at'))
	const endsAt = toIsoOrNull(formData.get('ends_at'))
	const metadataText = String(formData.get('metadata') ?? '').trim()
	const metadata = parseMetadata(metadataText)

	if (!title) return { ok: false as const, error: 'title_required' }
	if (!isAdCampaignType(campaignType)) return { ok: false as const, error: 'invalid_campaign_type' }
	if (!isAdCampaignFormat(format)) return { ok: false as const, error: 'invalid_format' }
	if (!isAdCampaignSurface(surface)) return { ok: false as const, error: 'invalid_surface' }
	if (!isAdCampaignStatus(requestedStatus)) return { ok: false as const, error: 'invalid_status' }
	if (!isAdCampaignApprovalStatus(requestedApproval)) return { ok: false as const, error: 'invalid_approval_status' }
	if (!metadata.ok) return { ok: false as const, error: metadata.error }
	if (startsAt && endsAt && new Date(endsAt).getTime() <= new Date(startsAt).getTime()) {
		return { ok: false as const, error: 'end_before_start' }
	}
	if (requestedApproval !== 'approved' && (requestedStatus === 'scheduled' || requestedStatus === 'active')) {
		return { ok: false as const, error: 'approval_required_for_scheduled_or_active' }
	}

	let status = requestedStatus
	if (requestedApproval === 'approved' && requestedStatus === 'draft' && requestedEnabled) {
		status = startsAt && new Date(startsAt).getTime() > Date.now() ? 'scheduled' : 'active'
	}

	const patch: Record<string, unknown> = {
		country_code: countryCode,
		campaign_type: campaignType,
		format,
		surface,
		title,
		description: String(formData.get('description') ?? '').trim() || null,
		sponsor_name: String(formData.get('sponsor_name') ?? '').trim() || null,
		asset_url: String(formData.get('asset_url') ?? '').trim() || null,
		video_url: String(formData.get('video_url') ?? '').trim() || null,
		cta_label: String(formData.get('cta_label') ?? '').trim() || null,
		cta_url: String(formData.get('cta_url') ?? '').trim() || null,
		audience: String(formData.get('audience') ?? '').trim() || null,
		target_type: String(formData.get('target_type') ?? '').trim() || null,
		target_ref_id: String(formData.get('target_ref_id') ?? '').trim() || null,
		starts_at: status === 'active' && !startsAt ? new Date().toISOString() : startsAt,
		ends_at: endsAt,
		frequency_cap_daily: parseNonNegativeInt(formData.get('frequency_cap_daily')),
		priority: parseNonNegativeInt(formData.get('priority')),
		status,
		approval_status: requestedApproval,
		is_enabled: requestedEnabled && requestedApproval === 'approved' && status !== 'completed' && status !== 'cancelled',
		rejection_reason: String(formData.get('rejection_reason') ?? '').trim() || null,
		metadata: metadata.value,
	}

	return { ok: true as const, patch }
}

function StatusPill(props: { value: string; tone: 'neutral' | 'success' | 'warning' | 'danger' | 'info' }) {
	const cls =
		props.tone === 'success'
			? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
			: props.tone === 'warning'
				? 'border-amber-500/30 bg-amber-500/10 text-amber-100'
				: props.tone === 'danger'
					? 'border-red-500/30 bg-red-500/10 text-red-100'
					: props.tone === 'info'
						? 'border-sky-500/30 bg-sky-500/10 text-sky-100'
						: 'border-white/10 bg-white/5 text-gray-200'
	return <span className={`inline-flex rounded-full border px-2 py-1 text-xs ${cls}`}>{props.value}</span>
}

function Stat(props: { label: string; value: string }) {
	return (
		<div className="rounded-xl border border-white/10 bg-black/20 p-4">
			<p className="text-xs text-gray-400">{props.label}</p>
			<p className="mt-1 text-lg font-semibold text-white">{props.value}</p>
		</div>
	)
}

export default async function AdCampaignsPage(props: { searchParams?: Promise<SearchParams> }) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!canManage(ctx.admin.role)) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">Only Ops and Super Admin can manage campaigns.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}

	const sp = (props.searchParams ? await props.searchParams : {}) ?? {}
	const country = await getAdminCountryCode()
	const countryConfig = await getCountryConfigByCode(country)
	const countryLabel = countryConfig?.country_name?.trim() ? `${countryConfig.country_name} (${country})` : country
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for Ad Campaigns" />

	let rows: AdCampaignRow[] = []
	let loadError: string | null = null

	const campaignsRes = await supabase
		.from('ad_campaigns')
		.select('id,country_code,campaign_type,format,surface,title,description,sponsor_name,asset_url,video_url,cta_label,cta_url,audience,target_type,target_ref_id,starts_at,ends_at,frequency_cap_daily,priority,status,approval_status,is_enabled,created_by,approved_by,approved_at,rejection_reason,metadata,created_at,updated_at')
		.eq('country_code', country)
		.order('priority', { ascending: false })
		.order('created_at', { ascending: false })
		.limit(250)

	if (campaignsRes.data && Array.isArray(campaignsRes.data)) {
		rows = campaignsRes.data as unknown as AdCampaignRow[]
	} else if (campaignsRes.error) {
		const msg = String(campaignsRes.error.message ?? '')
		if (/ad_campaigns|schema cache|could not find/i.test(msg)) {
			loadError = 'Campaigns table not yet in DB — run the ad_campaigns migration first.'
		} else {
			loadError = msg
		}
	}

	const editId = String(sp.edit ?? '').trim()
	const editing = rows.find((row) => row.id === editId) ?? null
	const liveCount = rows.filter(isLiveNow).length
	const pendingCount = rows.filter((row) => row.approval_status === 'pending').length
	const approvedCount = rows.filter((row) => row.approval_status === 'approved').length
	const disabledCount = rows.filter((row) => !row.is_enabled).length
	const adsStatus = countryConfig ? (countryConfig.ads_enabled ? 'Enabled' : 'Disabled') : 'Unknown'
	const marketStatus = countryConfig ? (countryConfig.is_active ? 'Active' : 'Disabled') : 'Unknown'

	async function upsertCampaign(formData: FormData) {
		'use server'

		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!canManage(ctx.admin.role)) redirect('/admin/ads/campaigns?error=forbidden')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/ads/campaigns?error=service_role_required')

		const id = String(formData.get('id') ?? '').trim()
		const built = buildCampaignPatch(formData, country)
		if (!built.ok) redirect(`/admin/ads/campaigns?error=${encodeURIComponent(built.error)}${id ? `&edit=${encodeURIComponent(id)}` : ''}`)

		const patch = built.patch as Record<string, unknown>
		let before: Record<string, unknown> | null = null
		if (id) {
			const { data } = await supabase.from('ad_campaigns').select('*').eq('id', id).maybeSingle()
			before = (data ?? null) as Record<string, unknown> | null
		}

		if (patch.approval_status === 'approved') {
			patch.approved_by = ctx.admin.email
			patch.approved_at = new Date().toISOString()
			patch.rejection_reason = null
		} else if (patch.approval_status === 'pending') {
			patch.approved_by = null
			patch.approved_at = null
		}

		if (!id) patch.created_by = ctx.admin.email

		const result = id
			? await supabase.from('ad_campaigns').update(patch).eq('id', id).select('id').maybeSingle()
			: await supabase.from('ad_campaigns').insert(patch).select('id').maybeSingle()

		if (result.error) {
			const suffix = id ? `&edit=${encodeURIComponent(id)}` : ''
			redirect(`/admin/ads/campaigns?error=${encodeURIComponent(String(result.error.message ?? 'save_failed'))}${suffix}`)
		}

		const targetId = String(result.data?.id ?? id)
		await logAdminAction({
			ctx,
			action: id ? 'ad_campaigns.update' : 'ad_campaigns.create',
			target_type: 'ad_campaign',
			target_id: targetId,
			before_state: before,
			after_state: patch,
			meta: { module: 'ads_campaigns', country_code: patch.country_code },
		})

		redirect(id ? '/admin/ads/campaigns?ok=updated' : '/admin/ads/campaigns?ok=created')
	}

	async function reviewCampaign(formData: FormData) {
		'use server'

		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!canManage(ctx.admin.role)) redirect('/admin/ads/campaigns?error=forbidden')

		const id = String(formData.get('id') ?? '').trim()
		const decision = String(formData.get('decision') ?? '').trim()
		const reason = String(formData.get('reason') ?? '').trim() || null
		if (!id) redirect('/admin/ads/campaigns?error=missing_id')
		if (!(decision === 'approved' || decision === 'rejected')) redirect('/admin/ads/campaigns?error=invalid_decision')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/ads/campaigns?error=service_role_required')

		const { data: before, error: beforeError } = await supabase.from('ad_campaigns').select('*').eq('id', id).maybeSingle()
		if (beforeError || !before) redirect('/admin/ads/campaigns?error=not_found')

		const nowIso = new Date().toISOString()
		const startsAt = before.starts_at ? new Date(before.starts_at).getTime() : null
		const patch: Record<string, unknown> = {
			approval_status: decision,
			approved_by: ctx.admin.email,
			approved_at: nowIso,
			rejection_reason: decision === 'rejected' ? reason : null,
		}

		if (decision === 'approved') {
			patch.is_enabled = true
			patch.status = before.status === 'draft'
				? startsAt != null && Number.isFinite(startsAt) && startsAt > Date.now()
					? 'scheduled'
					: 'active'
				: before.status
		} else {
			patch.is_enabled = false
			patch.status = before.status === 'completed' ? 'completed' : 'cancelled'
		}

		const { error } = await supabase.from('ad_campaigns').update(patch).eq('id', id)
		if (error) redirect(`/admin/ads/campaigns?error=${encodeURIComponent(String(error.message ?? 'review_failed'))}`)

		await logAdminAction({
			ctx,
			action: `ad_campaigns.${decision}`,
			target_type: 'ad_campaign',
			target_id: id,
			before_state: before as Record<string, unknown>,
			after_state: patch,
			meta: { module: 'ads_campaigns', country_code: before.country_code },
		})

		redirect(`/admin/ads/campaigns?ok=${encodeURIComponent(decision)}`)
	}

	async function setCampaignStatus(formData: FormData) {
		'use server'

		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!canManage(ctx.admin.role)) redirect('/admin/ads/campaigns?error=forbidden')

		const id = String(formData.get('id') ?? '').trim()
		const nextStatus = String(formData.get('status') ?? '').trim()
		if (!id) redirect('/admin/ads/campaigns?error=missing_id')
		if (!isAdCampaignStatus(nextStatus)) redirect('/admin/ads/campaigns?error=invalid_status')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/ads/campaigns?error=service_role_required')

		const { data: before, error: beforeError } = await supabase.from('ad_campaigns').select('*').eq('id', id).maybeSingle()
		if (beforeError || !before) redirect('/admin/ads/campaigns?error=not_found')
		if ((nextStatus === 'scheduled' || nextStatus === 'active') && before.approval_status !== 'approved') {
			redirect('/admin/ads/campaigns?error=approval_required_before_activation')
		}

		const patch: Record<string, unknown> = { status: nextStatus }
		if (nextStatus === 'active') {
			patch.is_enabled = true
			patch.starts_at = before.starts_at ?? new Date().toISOString()
		} else if (nextStatus === 'scheduled') {
			patch.is_enabled = true
		} else if (nextStatus === 'completed') {
			patch.is_enabled = false
			patch.ends_at = before.ends_at ?? new Date().toISOString()
		} else if (nextStatus === 'paused' || nextStatus === 'cancelled') {
			patch.is_enabled = false
		}

		const { error } = await supabase.from('ad_campaigns').update(patch).eq('id', id)
		if (error) redirect(`/admin/ads/campaigns?error=${encodeURIComponent(String(error.message ?? 'status_update_failed'))}`)

		await logAdminAction({
			ctx,
			action: 'ad_campaigns.set_status',
			target_type: 'ad_campaign',
			target_id: id,
			before_state: before as Record<string, unknown>,
			after_state: patch,
			meta: { module: 'ads_campaigns', country_code: before.country_code },
		})

		redirect(`/admin/ads/campaigns?ok=${encodeURIComponent(nextStatus)}`)
	}

	async function deleteCampaign(formData: FormData) {
		'use server'

		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		if (!canManage(ctx.admin.role)) redirect('/admin/ads/campaigns?error=forbidden')

		const id = String(formData.get('id') ?? '').trim()
		if (!id) redirect('/admin/ads/campaigns?error=missing_id')

		const supabase = tryCreateSupabaseAdminClient()
		if (!supabase) redirect('/admin/ads/campaigns?error=service_role_required')

		const { data: before, error: beforeError } = await supabase.from('ad_campaigns').select('*').eq('id', id).maybeSingle()
		if (beforeError || !before) redirect('/admin/ads/campaigns?error=not_found')

		const { error } = await supabase.from('ad_campaigns').delete().eq('id', id)
		if (error) redirect(`/admin/ads/campaigns?error=${encodeURIComponent(String(error.message ?? 'delete_failed'))}`)

		await logAdminAction({
			ctx,
			action: 'ad_campaigns.delete',
			target_type: 'ad_campaign',
			target_id: id,
			before_state: before as Record<string, unknown>,
			after_state: null,
			meta: { module: 'ads_campaigns', country_code: before.country_code },
		})

		redirect('/admin/ads/campaigns?ok=deleted')
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex flex-wrap items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Ad Campaigns</h1>
						<p className="mt-1 text-sm text-gray-400">Country-scoped control for AdMob, direct brand inventory, and in-app promotions.</p>
						<div className="mt-4 flex flex-wrap gap-3 text-xs text-gray-300">
							<span className="rounded-full border border-white/10 bg-black/20 px-3 py-1.5">Country: {countryLabel}</span>
							<span className="rounded-full border border-white/10 bg-black/20 px-3 py-1.5">Ads: {adsStatus}</span>
							<span className="rounded-full border border-white/10 bg-black/20 px-3 py-1.5">Market: {marketStatus}</span>
						</div>
					</div>
					<div className="flex flex-wrap gap-2">
						<Link href="/admin/ads" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Back</Link>
						<Link href={`/admin/countries/${encodeURIComponent(country)}`} className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Country settings</Link>
						<a href={`/api/ads/campaigns?country_code=${encodeURIComponent(country)}`} target="_blank" rel="noreferrer" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Preview API</a>
					</div>
				</div>
			</div>

			{sp.ok ? <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved: {sp.ok}</div> : null}
			{sp.error ? <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{sp.error}</div> : null}
			{loadError ? <div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">{loadError}</div> : null}

			<div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
				<Stat label="Total Campaigns" value={String(rows.length)} />
				<Stat label="Pending Approval" value={String(pendingCount)} />
				<Stat label="Approved" value={String(approvedCount)} />
				<Stat label="Live Now" value={String(liveCount)} />
			</div>

			<div className="grid gap-4 xl:grid-cols-[minmax(0,1.1fr),minmax(0,1.4fr)]">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<div className="flex items-start justify-between gap-4">
						<div>
							<h2 className="text-base font-semibold">{editing ? 'Edit campaign' : 'Create campaign'}</h2>
							<p className="mt-1 text-sm text-gray-400">Create per-country ad inventory with approval gates and lifecycle controls.</p>
						</div>
						{editing ? <Link href="/admin/ads/campaigns" className="text-xs text-gray-400 underline hover:text-gray-200">Clear edit</Link> : null}
					</div>

					<form action={upsertCampaign} className="mt-4 space-y-4">
						<input type="hidden" name="id" value={editing?.id ?? ''} />
						<input type="hidden" name="country_code" value={country} />

						<Field label="Title" name="title" defaultValue={editing?.title ?? ''} placeholder="MW Discover takeover" required />

						<div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
							<SelectField label="Campaign type" name="campaign_type" defaultValue={editing?.campaign_type ?? 'direct_brand'} options={AD_CAMPAIGN_TYPES.map((value) => ({ value, label: labelAdCampaignType(value) }))} />
							<SelectField label="Format" name="format" defaultValue={editing?.format ?? 'banner'} options={AD_CAMPAIGN_FORMATS.map((value) => ({ value, label: labelAdCampaignFormat(value) }))} />
							<SelectField label="Surface" name="surface" defaultValue={editing?.surface ?? 'home_banner'} options={AD_CAMPAIGN_SURFACES.map((value) => ({ value, label: labelAdCampaignSurface(value) }))} />
							<SelectField label="Status" name="status" defaultValue={editing?.status ?? 'draft'} options={AD_CAMPAIGN_STATUSES.map((value) => ({ value, label: labelAdCampaignStatus(value) }))} />
							<SelectField label="Approval" name="approval_status" defaultValue={editing?.approval_status ?? 'pending'} options={AD_CAMPAIGN_APPROVAL_STATUSES.map((value) => ({ value, label: labelAdCampaignApprovalStatus(value) }))} />
							<SelectField label="Enabled" name="is_enabled" defaultValue={String(editing?.is_enabled ?? false)} options={[{ value: 'false', label: 'Disabled' }, { value: 'true', label: 'Enabled' }]} />
						</div>

						<TextAreaField label="Description" name="description" defaultValue={editing?.description ?? ''} placeholder="Country launch copy, audience notes, or placement detail." rows={3} />

						<div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
							<Field label="Sponsor name" name="sponsor_name" defaultValue={editing?.sponsor_name ?? ''} placeholder="Brand / internal owner" />
							<Field label="Audience" name="audience" defaultValue={editing?.audience ?? ''} placeholder="all, free, premium, urban youth" />
							<Field label="CTA label" name="cta_label" defaultValue={editing?.cta_label ?? ''} placeholder="Install, Listen, Book now" />
							<Field label="CTA URL" name="cta_url" defaultValue={editing?.cta_url ?? ''} placeholder="https://... or weafrica://..." />
							<Field label="Asset URL" name="asset_url" defaultValue={editing?.asset_url ?? ''} placeholder="https://cdn.../banner.jpg" />
							<Field label="Video URL" name="video_url" defaultValue={editing?.video_url ?? ''} placeholder="https://cdn.../video.mp4" />
							<Field label="Target type" name="target_type" defaultValue={editing?.target_type ?? ''} placeholder="artist, dj, battle, ride" />
							<Field label="Target reference" name="target_ref_id" defaultValue={editing?.target_ref_id ?? ''} placeholder="artist_123 / battle_456" />
							<Field label="Starts at" name="starts_at" type="datetime-local" defaultValue={toDateTimeLocalValue(editing?.starts_at)} />
							<Field label="Ends at" name="ends_at" type="datetime-local" defaultValue={toDateTimeLocalValue(editing?.ends_at)} />
							<Field label="Frequency cap / day" name="frequency_cap_daily" type="number" defaultValue={String(editing?.frequency_cap_daily ?? 0)} placeholder="0" />
							<Field label="Priority" name="priority" type="number" defaultValue={String(editing?.priority ?? 0)} placeholder="0" />
						</div>

						<TextAreaField label="Rejection reason" name="rejection_reason" defaultValue={editing?.rejection_reason ?? ''} placeholder="Only needed when rejected or blocked." rows={2} />
						<TextAreaField label="Metadata (JSON object)" name="metadata" defaultValue={editing?.metadata ? JSON.stringify(editing.metadata, null, 2) : '{}'} placeholder='{"placement":"homepage_top"}' rows={6} />

						<div className="flex flex-wrap gap-2">
							<button type="submit" className="inline-flex h-10 items-center rounded-xl bg-white px-4 text-sm font-medium text-black hover:bg-white/90">{editing ? 'Update campaign' : 'Create campaign'}</button>
							{editing ? <Link href="/admin/ads/campaigns" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Cancel</Link> : null}
						</div>
					</form>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h2 className="text-base font-semibold">Operational readiness</h2>
					<ul className="mt-3 space-y-2 text-sm text-gray-300">
						<li>- Approval required before campaigns can go live.</li>
						<li>- Consumer API only returns approved, enabled campaigns inside their live schedule window.</li>
						<li>- Frequency cap 0 means unlimited impressions per user per day.</li>
						<li>- In-app promo campaigns can point to artists, DJs, battles, events, or ride targets.</li>
					</ul>
					<div className="mt-6 grid gap-3 sm:grid-cols-2">
						<Stat label="Disabled" value={String(disabledCount)} />
						<Stat label="Country code" value={country} />
					</div>
				</div>
			</div>

			<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
				<div className="overflow-x-auto">
					<table className="min-w-[1320px] w-full text-sm">
						<thead className="bg-black/20 text-left text-xs text-gray-400">
							<tr>
								<th className="px-4 py-3">Campaign</th>
								<th className="px-4 py-3">Type</th>
								<th className="px-4 py-3">Surface</th>
								<th className="px-4 py-3">Schedule</th>
								<th className="px-4 py-3">Review</th>
								<th className="px-4 py-3">Delivery</th>
								<th className="px-4 py-3 text-right">Actions</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10">
							{rows.length ? (
								rows.map((row) => (
									<tr key={row.id} className="align-top hover:bg-white/5">
										<td className="px-4 py-3">
											<div className="font-medium text-white">{row.title}</div>
											<div className="mt-1 text-xs text-gray-400">Sponsor: {row.sponsor_name ?? '—'}</div>
											<div className="mt-1 text-xs text-gray-500">Created by {row.created_by ?? '—'} • {fmtDate(row.created_at)}</div>
										</td>
										<td className="px-4 py-3 text-gray-200">
											<div>{labelAdCampaignType(row.campaign_type)}</div>
											<div className="mt-1 text-xs text-gray-500">{labelAdCampaignFormat(row.format)}</div>
											{row.target_type || row.target_ref_id ? <div className="mt-1 text-xs text-gray-500">{row.target_type ?? 'target'}: {row.target_ref_id ?? '—'}</div> : null}
										</td>
										<td className="px-4 py-3 text-gray-200">
											<div>{labelAdCampaignSurface(row.surface)}</div>
											<div className="mt-1 text-xs text-gray-500">Priority {row.priority} • Cap {row.frequency_cap_daily}/day</div>
											{row.audience ? <div className="mt-1 text-xs text-gray-500">Audience: {row.audience}</div> : null}
										</td>
										<td className="px-4 py-3 text-xs text-gray-300">
											<div>Start: {fmtDate(row.starts_at)}</div>
											<div>End: {fmtDate(row.ends_at)}</div>
											<div className="mt-1 text-gray-500">Updated: {fmtDate(row.updated_at)}</div>
										</td>
										<td className="px-4 py-3">
											<div className="flex flex-wrap gap-2">
												<StatusPill value={labelAdCampaignApprovalStatus(row.approval_status)} tone={row.approval_status === 'approved' ? 'success' : row.approval_status === 'rejected' ? 'danger' : 'warning'} />
												<StatusPill value={labelAdCampaignStatus(row.status)} tone={row.status === 'active' ? 'success' : row.status === 'scheduled' ? 'info' : row.status === 'paused' ? 'warning' : row.status === 'completed' || row.status === 'cancelled' ? 'danger' : 'neutral'} />
											</div>
											<div className="mt-2 text-xs text-gray-500">Approved by: {row.approved_by ?? '—'}</div>
											{row.rejection_reason ? <div className="mt-1 text-xs text-red-200">Reason: {row.rejection_reason}</div> : null}
										</td>
										<td className="px-4 py-3">
											<div className="text-gray-200">{row.is_enabled ? 'Enabled' : 'Disabled'}</div>
											<div className="mt-1 text-xs text-gray-500">{isLiveNow(row) ? 'Live in API' : 'Not currently served'}</div>
											{row.asset_url ? <div className="mt-1 truncate text-xs text-gray-500">Asset: {row.asset_url}</div> : null}
										</td>
										<td className="px-4 py-3">
											<div className="flex flex-wrap justify-end gap-2">
												<Link href={`/admin/ads/campaigns?edit=${encodeURIComponent(row.id)}`} className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">Edit</Link>
												<form action={reviewCampaign}>
													<input type="hidden" name="id" value={row.id} />
													<input type="hidden" name="decision" value="approved" />
													<button className="h-9 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 text-xs text-emerald-200 hover:bg-emerald-500/15">Approve</button>
												</form>
												<form action={reviewCampaign}>
													<input type="hidden" name="id" value={row.id} />
													<input type="hidden" name="decision" value="rejected" />
													<input type="hidden" name="reason" value="Rejected by ops from campaigns table" />
													<button className="h-9 rounded-xl border border-red-500/30 bg-red-500/10 px-3 text-xs text-red-100 hover:bg-red-500/15">Reject</button>
												</form>
												<form action={setCampaignStatus}>
													<input type="hidden" name="id" value={row.id} />
													<input type="hidden" name="status" value={row.status === 'active' ? 'paused' : 'active'} />
													<button className="h-9 rounded-xl border border-white/10 px-3 text-xs hover:bg-white/5">{row.status === 'active' ? 'Pause' : 'Activate'}</button>
												</form>
												<form action={deleteCampaign}>
													<input type="hidden" name="id" value={row.id} />
													<button className="h-9 rounded-xl border border-white/10 px-3 text-xs text-gray-300 hover:bg-white/5">Delete</button>
												</form>
											</div>
										</td>
									</tr>
								))
							) : (
								<tr>
									<td className="px-4 py-8 text-center text-sm text-gray-400" colSpan={7}>No campaigns yet for {countryLabel}. Create the first one from the form above.</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>
		</div>
	)
}

function Field(props: { label: string; name: string; defaultValue?: string; placeholder?: string; type?: string; required?: boolean }) {
	return (
		<label className="block">
			<span className="block text-sm text-gray-300">{props.label}</span>
			<input
				name={props.name}
				type={props.type ?? 'text'}
				defaultValue={props.defaultValue ?? ''}
				placeholder={props.placeholder}
				required={props.required}
				className="mt-2 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none"
			/>
		</label>
	)
}

function SelectField(props: { label: string; name: string; defaultValue: string; options: Array<{ value: string; label: string }> }) {
	return (
		<label className="block">
			<span className="block text-sm text-gray-300">{props.label}</span>
			<select name={props.name} defaultValue={props.defaultValue} className="mt-2 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none">
				{props.options.map((option) => (
					<option key={option.value} value={option.value}>{option.label}</option>
				))}
			</select>
		</label>
	)
}

function TextAreaField(props: { label: string; name: string; defaultValue?: string; placeholder?: string; rows?: number }) {
	return (
		<label className="block">
			<span className="block text-sm text-gray-300">{props.label}</span>
			<textarea
				name={props.name}
				defaultValue={props.defaultValue ?? ''}
				placeholder={props.placeholder}
				rows={props.rows ?? 4}
				className="mt-2 w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm outline-none"
			/>
		</label>
	)
}
