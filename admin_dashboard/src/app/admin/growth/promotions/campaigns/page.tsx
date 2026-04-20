import Link from 'next/link'
import { redirect } from 'next/navigation'

import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import {
	PROMOTION_PLAN_CONFIG,
	buildPromotionShareMessage,
	buildPromotionShareUrl,
	daysRemaining,
	labelPromotionPlan,
	labelPromotionType,
	normalizePaidPromotionStatus,
	normalizePromotionPlan,
	promotionPlanCoins,
	promotionPlanPlatforms,
	type PromotionPlan,
	type PromotionSocialPlatform,
} from '@/lib/admin/promotions'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type PromotionRow = {
	id: string
	title: string | null
	user_id: string | null
	content_id: string | null
	target_id: string | null
	content_type: string | null
	promotion_type: string | null
	plan: string | null
	status: string | null
	start_date: string | null
	end_date: string | null
	starts_at: string | null
	ends_at: string | null
	facebook_page_url: string | null
	instagram_url: string | null
	x_url: string | null
	whatsapp_channel_url: string | null
	created_at: string
}

type PaidPromotionRow = {
	id: string
	title: string | null
	user_id: string | null
	content_id: string | null
	content_type: string | null
	plan: string | null
	duration_days: number | null
	coins: number | null
	status: string | null
	created_at: string
	facebook_page_url: string | null
	instagram_url: string | null
	x_url: string | null
	whatsapp_channel_url: string | null
}

type PromotionPostRow = {
	promotion_id: string
	platform: PromotionSocialPlatform
	status: 'pending' | 'posted' | 'skipped'
}

type PromotionEventRow = {
	promotion_id: string | null
	event_type: string | null
}

type PromotionSummaryRow = {
	id: string
	title: string
	userId: string
	contentId: string
	contentType: string
	plan: PromotionPlan
	status: string
	startIso: string | null
	endIso: string | null
	createdAt: string
	socialLinks: Record<PromotionSocialPlatform, string>
}

function fmtDate(iso: string | null | undefined): string {
	if (!iso) return '—'
	const date = new Date(iso)
	if (Number.isNaN(date.getTime())) return String(iso)
	return date.toLocaleString()
}

function badgeClass(tone: 'neutral' | 'warning' | 'success' | 'danger' | 'info'): string {
	if (tone === 'success') return 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
	if (tone === 'warning') return 'border-amber-500/30 bg-amber-500/10 text-amber-100'
	if (tone === 'danger') return 'border-red-500/30 bg-red-500/10 text-red-100'
	if (tone === 'info') return 'border-sky-500/30 bg-sky-500/10 text-sky-100'
	return 'border-white/10 bg-white/5 text-gray-200'
}

function statusTone(status: string): 'neutral' | 'warning' | 'success' | 'danger' | 'info' {
	const s = status.trim().toLowerCase()
	if (s === 'active' || s === 'approved' || s === 'completed') return 'success'
	if (s === 'pending' || s === 'paused') return 'warning'
	if (s === 'scheduled') return 'info'
	if (s === 'ended' || s === 'rejected' || s === 'cancelled') return 'danger'
	return 'neutral'
}

function normalizePromotionRow(row: PromotionRow): PromotionSummaryRow {
	return {
		id: row.id,
		title: row.title?.trim() || 'Untitled promotion',
		userId: row.user_id?.trim() || '—',
		contentId: row.content_id?.trim() || row.target_id?.trim() || '—',
		contentType: row.content_type?.trim() || row.promotion_type?.trim() || 'song',
		plan: normalizePromotionPlan(row.plan),
		status: row.status?.trim() || 'draft',
		startIso: row.start_date ?? row.starts_at,
		endIso: row.end_date ?? row.ends_at,
		createdAt: row.created_at,
		socialLinks: {
			facebook: row.facebook_page_url?.trim() || '',
			instagram: row.instagram_url?.trim() || '',
			x: row.x_url?.trim() || '',
			whatsapp: row.whatsapp_channel_url?.trim() || '',
		},
	}
}

function normalizePendingRow(row: PaidPromotionRow): PromotionSummaryRow {
	return {
		id: row.id,
		title: row.title?.trim() || 'Promotion request',
		userId: row.user_id?.trim() || '—',
		contentId: row.content_id?.trim() || '—',
		contentType: row.content_type?.trim() || 'song',
		plan: normalizePromotionPlan(row.plan ?? (row.coins != null ? (row.coins >= 500 ? 'premium' : row.coins >= 200 ? 'pro' : 'basic') : 'basic')),
		status: normalizePaidPromotionStatus(row.status),
		startIso: null,
		endIso: null,
		createdAt: row.created_at,
		socialLinks: {
			facebook: row.facebook_page_url?.trim() || '',
			instagram: row.instagram_url?.trim() || '',
			x: row.x_url?.trim() || '',
			whatsapp: row.whatsapp_channel_url?.trim() || '',
		},
	}
}

function postSummary(rows: PromotionPostRow[], promotionId: string): string {
	const scoped = rows.filter((row) => row.promotion_id === promotionId)
	if (!scoped.length) return 'No social posts logged yet'
	const posted = scoped.filter((row) => row.status === 'posted').length
	return `${posted}/${scoped.length} channels posted`
}

function eventSummary(rows: PromotionEventRow[], promotionId: string): string {
	const scoped = rows.filter((row) => row.promotion_id === promotionId)
	if (!scoped.length) return 'Views 0 • Clicks 0'
	const views = scoped.filter((row) => row.event_type === 'view').length
	const clicks = scoped.filter((row) => row.event_type === 'click').length
	return `Views ${views.toLocaleString()} • Clicks ${clicks.toLocaleString()}`
}

function SocialButtons(props: { row: PromotionSummaryRow }) {
	const contentUrl = `https://weafricamusic.com/promotions/${encodeURIComponent(props.row.id)}`
	const allowed = promotionPlanPlatforms(props.row.plan)
	if (!allowed.length) {
		return <span className="text-xs text-gray-500">In-app boost only</span>
	}

	return (
		<div className="flex flex-wrap gap-2">
			{allowed.map((platform) => {
				const href = buildPromotionShareUrl({
					platform,
					title: props.row.title,
					artistName: props.row.userId,
					plan: props.row.plan,
					contentUrl,
					overrideLink: props.row.socialLinks[platform],
				})
				const label = platform === 'facebook' ? 'FB' : platform === 'instagram' ? 'IG' : platform === 'whatsapp' ? 'WA' : 'X'
				return (
					<a
						key={platform}
						href={href}
						target="_blank"
						rel="noreferrer"
						className="inline-flex h-9 items-center rounded-xl border border-white/10 px-3 text-xs text-gray-100 hover:bg-white/5"
					>
						{label}
					</a>
				)
			})}
		</div>
	)
}

function PromotionSection(props: {
	title: string
	description: string
	rows: PromotionSummaryRow[]
	posts: PromotionPostRow[]
	events: PromotionEventRow[]
	empty: string
	showDaysLeft?: boolean
	showPerformance?: boolean
}) {
	const columnCount = props.showDaysLeft && props.showPerformance ? 7 : props.showDaysLeft || props.showPerformance ? 6 : 5

	return (
		<div className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
			<div className="border-b border-white/10 px-5 py-4">
				<h2 className="text-sm font-semibold text-white">{props.title}</h2>
				<p className="mt-1 text-xs text-gray-400">{props.description}</p>
			</div>
			<div className="overflow-x-auto">
				<table className="min-w-[1080px] w-full text-sm">
					<thead className="bg-black/20 text-left text-xs text-gray-400">
						<tr>
							<th className="px-4 py-3">Artist / Content</th>
							<th className="px-4 py-3">Plan</th>
							<th className="px-4 py-3">Status</th>
							<th className="px-4 py-3">Schedule</th>
							{props.showDaysLeft ? <th className="px-4 py-3">Days Left</th> : null}
							<th className="px-4 py-3">Social Actions</th>
							{props.showPerformance ? <th className="px-4 py-3">Performance</th> : null}
						</tr>
					</thead>
					<tbody className="divide-y divide-white/10">
						{props.rows.length ? (
							props.rows.map((row) => {
								const shareMessage = buildPromotionShareMessage({
									title: row.title,
									artistName: row.userId,
									plan: row.plan,
									contentUrl: `https://weafricamusic.com/promotions/${encodeURIComponent(row.id)}`,
								})
								return (
									<tr key={row.id} className="hover:bg-white/5 align-top">
										<td className="px-4 py-3">
											<div className="font-medium text-white">{row.title}</div>
											<div className="mt-1 text-xs text-gray-400">Creator: {row.userId}</div>
											<div className="mt-1 text-xs text-gray-500">{labelPromotionType(row.contentType)} • {row.contentId}</div>
										</td>
										<td className="px-4 py-3 text-gray-200">
											<div className="font-medium">{labelPromotionPlan(row.plan)}</div>
											<div className="mt-1 text-xs text-gray-500">{promotionPlanCoins(row.plan).toLocaleString()} coins</div>
										</td>
										<td className="px-4 py-3">
											<span className={`inline-flex rounded-full border px-2 py-1 text-xs ${badgeClass(statusTone(row.status))}`}>
												{row.status}
											</span>
											<div className="mt-2 text-xs text-gray-500">{postSummary(props.posts, row.id)}</div>
										</td>
										<td className="px-4 py-3 text-xs text-gray-300">
											<div>Start: {fmtDate(row.startIso)}</div>
											<div>End: {fmtDate(row.endIso)}</div>
											<div className="mt-1 text-gray-500">Created: {fmtDate(row.createdAt)}</div>
										</td>
										{props.showDaysLeft ? <td className="px-4 py-3 text-gray-200">{daysRemaining(row.endIso)}</td> : null}
										<td className="px-4 py-3">
											<SocialButtons row={row} />
											<p className="mt-2 max-w-md text-xs text-gray-500">{shareMessage}</p>
										</td>
										{props.showPerformance ? <td className="px-4 py-3 text-xs text-gray-300">{eventSummary(props.events, row.id)}</td> : null}
									</tr>
								)
							})
						) : (
							<tr>
								<td colSpan={columnCount} className="px-4 py-8 text-center text-sm text-gray-400">
									{props.empty}
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	)
}

export default async function GrowthCampaignsPage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const country = await getAdminCountryCode()
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for promotions overview" />

	let promotionRows: PromotionRow[] = []
	let paidRows: PaidPromotionRow[] = []
	let postRows: PromotionPostRow[] = []
	let eventRows: PromotionEventRow[] = []
	let loadWarning: string | null = null

	const [promotionsRes, paidRes, postsRes, eventsRes] = await Promise.all([
		supabase
			.from('promotions')
			.select('id,title,user_id,content_id,target_id,content_type,promotion_type,plan,status,start_date,end_date,starts_at,ends_at,facebook_page_url,instagram_url,x_url,whatsapp_channel_url,created_at')
			.order('created_at', { ascending: false })
			.limit(150),
		supabase
			.from('paid_promotions')
			.select('id,title,user_id,content_id,content_type,plan,duration_days,coins,status,created_at,facebook_page_url,instagram_url,x_url,whatsapp_channel_url')
			.order('created_at', { ascending: false })
			.limit(150),
		supabase.from('promotion_posts').select('promotion_id,platform,status').limit(1000),
		supabase.from('promotion_events').select('promotion_id,event_type').limit(5000),
	])

	if (promotionsRes.data && Array.isArray(promotionsRes.data)) {
		promotionRows = promotionsRes.data as PromotionRow[]
	} else if (promotionsRes.error) {
		loadWarning = String(promotionsRes.error.message ?? 'Failed to load promotions data')
	}

	if (paidRes.data && Array.isArray(paidRes.data)) {
		paidRows = paidRes.data as PaidPromotionRow[]
	} else if (!loadWarning && paidRes.error) {
		loadWarning = String(paidRes.error.message ?? 'Failed to load paid promotions')
	}

	if (postsRes.data && Array.isArray(postsRes.data)) {
		postRows = postsRes.data as PromotionPostRow[]
	}

	if (eventsRes.data && Array.isArray(eventsRes.data)) {
		eventRows = eventsRes.data as PromotionEventRow[]
	}

	const normalizedPromotions = promotionRows.map(normalizePromotionRow)
	const active = normalizedPromotions.filter((row) => row.status === 'active')
	const completed = normalizedPromotions.filter((row) => row.status === 'ended' || row.status === 'completed')
	const pending = paidRows.map(normalizePendingRow).filter((row) => row.status === 'pending')
	const total = normalizedPromotions.length + pending.length

	const planCounts = normalizedPromotions.reduce(
		(acc, row) => {
			acc[row.plan] += 1
			return acc
		},
		{ basic: 0, pro: 0, premium: 0 } as Record<PromotionPlan, number>,
	)

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex flex-wrap items-start justify-between gap-4">
					<div>
						<h1 className="text-xl font-semibold text-white">Promotions System</h1>
						<p className="mt-2 max-w-3xl text-sm text-gray-400">
							Unified view of paid promotion requests, active boosts, completion state, social posting, and the plan tiers that affect feed weight.
						</p>
						<p className="mt-2 text-xs text-gray-500">Country scope: {country}</p>
					</div>
					<div className="flex flex-wrap gap-2">
						<Link href="/admin/ads/paid-promotions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Paid Queue
						</Link>
						<Link href="/admin/ads/admin-promotions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Admin Campaigns
						</Link>
					</div>
				</div>
			</div>

			{loadWarning ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">{loadWarning}</div>
			) : null}

			<div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
				{[
					{ label: 'Total Promotions', value: total.toLocaleString() },
					{ label: 'Pending Approval', value: pending.length.toLocaleString() },
					{ label: 'Active Promotions', value: active.length.toLocaleString() },
					{ label: 'Completed Promotions', value: completed.length.toLocaleString() },
				].map((card) => (
					<div key={card.label} className="rounded-xl border border-white/10 bg-black/20 p-4">
						<p className="text-xs text-gray-400">{card.label}</p>
						<p className="mt-1 text-2xl font-semibold text-white">{card.value}</p>
					</div>
				))}
			</div>

			<div className="grid gap-6 xl:grid-cols-[1.3fr_1fr]">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
					<h2 className="text-sm font-semibold text-white">Promotion Status Flow</h2>
					<div className="mt-4 grid gap-3 md:grid-cols-4">
						{[
							{ title: 'Pending', copy: 'Creator spends coins and waits for review.' },
							{ title: 'Approved', copy: 'Ops validates content, plan, and timing.' },
							{ title: 'Active', copy: 'Feed bonus and social posting are live.' },
							{ title: 'Completed', copy: 'Campaign expires and moves to reporting.' },
						].map((step, index) => (
							<div key={step.title} className="rounded-xl border border-white/10 bg-black/20 p-4">
								<p className="text-xs text-gray-500">Step {index + 1}</p>
								<p className="mt-1 font-medium text-white">{step.title}</p>
								<p className="mt-2 text-xs text-gray-400">{step.copy}</p>
							</div>
						))}
					</div>
				</div>

				<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
					<h2 className="text-sm font-semibold text-white">Social Channels</h2>
					<div className="mt-4 space-y-3 text-sm text-gray-300">
						<div className="rounded-xl border border-white/10 bg-black/20 p-3">Facebook / IG page: WeAfrica Music official pages</div>
						<div className="rounded-xl border border-white/10 bg-black/20 p-3">X and WhatsApp are enabled only for Premium plans.</div>
						<div className="rounded-xl border border-white/10 bg-black/20 p-3">Instagram uses manual posting flow: open the page and copy the generated caption shown per row.</div>
					</div>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-5">
				<h2 className="text-sm font-semibold text-white">Plan Economics</h2>
				<div className="mt-4 overflow-x-auto">
					<table className="min-w-[720px] w-full text-sm">
						<thead className="text-left text-xs text-gray-400">
							<tr>
								<th className="py-2">Plan</th>
								<th className="py-2">Coins</th>
								<th className="py-2">Feed Weight</th>
								<th className="py-2">Social Media</th>
								<th className="py-2">Featured Badge</th>
								<th className="py-2">Current Volume</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/10 text-gray-200">
							{(Object.entries(PROMOTION_PLAN_CONFIG) as Array<[PromotionPlan, (typeof PROMOTION_PLAN_CONFIG)[PromotionPlan]]>).map(([plan, config]) => (
								<tr key={plan}>
									<td className="py-3 font-medium text-white">{config.label}</td>
									<td className="py-3">{config.coins.toLocaleString()}</td>
									<td className="py-3">x{config.feedWeight}</td>
									<td className="py-3">{config.socialPlatforms.length ? config.socialPlatforms.join(', ') : 'None'}</td>
									<td className="py-3">{config.featuredBadge ? 'Yes' : 'No'}</td>
									<td className="py-3">{planCounts[plan].toLocaleString()}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			</div>

			<PromotionSection
				title="Active Promotions"
				description="Campaigns currently contributing feed bonus and eligible for social posting."
				rows={active}
				posts={postRows}
				events={eventRows}
				empty="No active promotions."
				showDaysLeft
			/>

			<PromotionSection
				title="Pending Approval"
				description="Requests waiting for Ops review before they can become active promotions."
				rows={pending}
				posts={postRows}
				events={eventRows}
				empty="No pending requests."
			/>

			<PromotionSection
				title="Completed Promotions"
				description="Ended campaigns with final engagement snapshots and posting coverage."
				rows={completed}
				posts={postRows}
				events={eventRows}
				empty="No completed promotions yet."
				showPerformance
			/>
		</div>
	)
}
