import Link from 'next/link'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import StatsCard from '@/components/admin/StatsCard'
import { getAdminContext } from '@/lib/admin/session'
import { getAdminCountryCode } from '@/lib/country/context'
import { adminBackendFetchJson } from '@/lib/admin/backend'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getPendingApprovalsCount } from '@/lib/admin/pendingApprovals'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type Snapshot = {
	totalUsers: number | null
	totalArtists: number | null
	totalDjs: number | null
	totalConsumers: number | null
	totalSongs: number | null
	activeSubscriptions: number | null
	revenue30d: number | null
	liveNow: number | null
	pendingApprovals: number | null
	blockedAccounts: number | null
	openReports: number | null
	activeBattles: number | null
	viralItems: Array<{ id?: string; title?: string | null; item_type?: string; score?: number | string | null; view_count?: number | null }>
}

function formatNumber(value: number | null): string {
	if (value == null) return '—'
	return new Intl.NumberFormat().format(value)
}

function formatMoneyMwk(value: number | null): string {
	if (value == null) return '—'
	return `MWK ${new Intl.NumberFormat().format(Math.round(value))}`
}

async function loadSnapshot(): Promise<Snapshot> {
	type DashboardPayload = {
		metrics?: {
			total_users?: number | null
			total_songs?: number | null
			total_videos?: number | null
			total_battles?: number | null
			total_revenue?: number | null
		}
		realtime?: {
			active_users?: number | null
			active_streams?: number | null
			active_battles?: number | null
		}
		moderation?: {
			pending_flags?: number | null
		}
		viral?: Snapshot['viralItems']
	}

	type RealtimePayload = {
		active_users?: number | null
		active_streams?: number | null
		active_battles?: number | null
	}

	type ViralPayload = Snapshot['viralItems']

	try {
		const supabase = tryCreateSupabaseAdminClient()
		const [dashboard, realtime, viral, pendingApprovals] = await Promise.all([
			adminBackendFetchJson<DashboardPayload>('/admin/dashboard'),
			adminBackendFetchJson<RealtimePayload>('/admin/metrics/realtime'),
			adminBackendFetchJson<ViralPayload>('/admin/viral'),
			supabase ? getPendingApprovalsCount(supabase) : Promise.resolve(null),
		])

		return {
			totalUsers: dashboard.metrics?.total_users ?? null,
			totalArtists: null,
			totalDjs: null,
			totalConsumers: null,
			totalSongs: dashboard.metrics?.total_songs ?? null,
			activeSubscriptions: null,
			revenue30d: dashboard.metrics?.total_revenue ?? null,
			liveNow: realtime.active_streams ?? dashboard.realtime?.active_streams ?? null,
			pendingApprovals,
			blockedAccounts: null,
			openReports: dashboard.moderation?.pending_flags ?? null,
			activeBattles: realtime.active_battles ?? dashboard.realtime?.active_battles ?? null,
			viralItems: Array.isArray(viral) ? viral.slice(0, 5) : Array.isArray(dashboard.viral) ? dashboard.viral.slice(0, 5) : [],
		}
	} catch {
		return {
			totalUsers: null,
			totalArtists: null,
			totalDjs: null,
			totalConsumers: null,
			totalSongs: null,
			activeSubscriptions: null,
			revenue30d: null,
			liveNow: null,
			pendingApprovals: null,
			blockedAccounts: null,
			openReports: null,
			activeBattles: null,
			viralItems: [],
		}
	}
}

function ActionAreaCard(props: {
	title: string
	description: string
	href: string
	actions: string[]
	badge?: string
}) {
	return (
		<Link href={props.href} className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5 transition hover:bg-zinc-900/70">
			<div className="flex items-start justify-between gap-3">
				<div>
					<h2 className="text-base font-semibold text-white">{props.title}</h2>
					<p className="mt-1 text-sm text-zinc-400">{props.description}</p>
				</div>
				{props.badge ? <span className="rounded-full border border-white/10 bg-white/5 px-2 py-1 text-[11px] text-zinc-300">{props.badge}</span> : null}
			</div>
			<ul className="mt-4 space-y-1.5 text-sm text-zinc-300">
				{props.actions.map((action) => (
					<li key={action}>• {action}</li>
				))}
			</ul>
			<div className="mt-4 text-xs text-zinc-500">Open area →</div>
		</Link>
	)
}

function MenuGroupCard(props: { title: string; href: string; items: string[] }) {
	return (
		<Link href={props.href} className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-5 transition hover:bg-zinc-900/60">
			<h3 className="text-sm font-semibold text-white">{props.title}</h3>
			<ul className="mt-3 space-y-1.5 text-sm text-zinc-400">
				{props.items.map((item) => (
					<li key={item}>• {item}</li>
				))}
			</ul>
		</Link>
	)
}

export default async function DashboardPage() {
	const user = await verifyFirebaseSessionCookie()
	const ctx = await getAdminContext()
	const country = await getAdminCountryCode()
	const snapshot = await loadSnapshot()

	return (
		<div className="space-y-8">
			<div className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6">
				<div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
					<div>
						<p className="text-sm text-zinc-300">Admin Dashboard</p>
						<h1 className="mt-1 text-2xl font-bold text-white">Operations control center</h1>
						<p className="mt-2 max-w-3xl text-sm text-zinc-400">
							This dashboard is now structured around the 5 strongest admin areas you requested: users, content,
							live streaming, payments & coins, and platform analytics.
						</p>
					</div>
					<div className="grid grid-cols-1 gap-2 text-sm text-zinc-300 sm:grid-cols-3 lg:min-w-[420px]">
						<div className="rounded-xl border border-zinc-800 bg-black/20 p-3">
							<div className="text-xs text-zinc-500">Signed in</div>
							<div className="mt-1 truncate font-medium">{user?.email ?? user?.uid ?? '—'}</div>
						</div>
						<div className="rounded-xl border border-zinc-800 bg-black/20 p-3">
							<div className="text-xs text-zinc-500">Admin role</div>
							<div className="mt-1 font-medium">{ctx?.admin.role ?? '—'}</div>
						</div>
						<div className="rounded-xl border border-zinc-800 bg-black/20 p-3">
							<div className="text-xs text-zinc-500">Country scope</div>
							<div className="mt-1 font-medium">{country || '—'}</div>
						</div>
					</div>
				</div>
			</div>

			<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
				<StatsCard title="Total Users" value={formatNumber(snapshot.totalUsers)} hint="Artists + DJs + Consumers" />
				<StatsCard title="Artists" value={formatNumber(snapshot.totalArtists)} hint="Manage, verify, block, subscribe" />
				<StatsCard title="DJs" value={formatNumber(snapshot.totalDjs)} hint="Manage, block, subscribe" />
				<StatsCard title="Consumers" value={formatNumber(snapshot.totalConsumers)} hint="View, edit, block, subscribe" />
				<StatsCard title="Songs" value={formatNumber(snapshot.totalSongs)} hint="Total uploaded songs" />
				<StatsCard title="Active Subscriptions" value={formatNumber(snapshot.activeSubscriptions)} hint="Manual and paid" />
				<StatsCard title="Revenue (30d)" value={formatMoneyMwk(snapshot.revenue30d)} hint="Coin purchases + subscriptions + ads" />
				<StatsCard title="Live Streams Now" value={formatNumber(snapshot.liveNow)} hint="Monitor Agora sessions" />
				<StatsCard title="Active Battles" value={formatNumber(snapshot.activeBattles)} hint="Live competition status" />
				<StatsCard title="Pending Approvals" value={formatNumber(snapshot.pendingApprovals)} hint="Creators + tracks waiting" />
				<StatsCard title="Open Reports" value={formatNumber(snapshot.openReports)} hint="Needs moderation review" />
			</div>

			<div className="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6">
				<div className="flex items-start justify-between gap-3">
					<div>
						<h2 className="text-lg font-semibold text-white">Viral Now</h2>
						<p className="mt-1 text-sm text-zinc-400">Top feed items ordered by the backend admin API.</p>
					</div>
					<Link href="/admin/analytics" className="text-sm text-zinc-300 underline hover:text-white">
						Open analytics
					</Link>
				</div>

				{snapshot.viralItems.length ? (
					<div className="mt-4 grid grid-cols-1 gap-3 xl:grid-cols-5">
						{snapshot.viralItems.map((item, index) => (
							<div key={item.id ?? `${item.item_type ?? 'item'}-${index}`} className="rounded-xl border border-zinc-800 bg-black/20 p-4">
								<div className="text-xs uppercase tracking-wide text-zinc-500">{item.item_type ?? 'item'}</div>
								<div className="mt-2 line-clamp-2 text-sm font-medium text-white">{item.title || item.id || 'Untitled item'}</div>
								<div className="mt-3 text-xs text-zinc-400">Score: {formatNumber(typeof item.score === 'string' ? Number(item.score) : item.score ?? null)}</div>
								<div className="mt-1 text-xs text-zinc-500">Views: {formatNumber(item.view_count ?? null)}</div>
							</div>
						))}
					</div>
				) : (
					<div className="mt-4 rounded-xl border border-zinc-800 bg-black/20 p-4 text-sm text-zinc-400">No viral feed items returned by the backend yet.</div>
				)}
			</div>

			<div className="space-y-4">
				<div>
					<h2 className="text-lg font-semibold text-white">1. What Admin can do</h2>
					<p className="mt-1 text-sm text-zinc-400">Full operational powers, grouped by the areas you outlined.</p>
				</div>
				<div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
					<ActionAreaCard
						title="User Management"
						description="Control artists, DJs, and consumers from a single admin surface."
						href="/admin/users"
						badge={snapshot.blockedAccounts == null ? undefined : `${formatNumber(snapshot.blockedAccounts)} blocked`}
						actions={[
							'View, search, and filter all users by type',
							'Edit, block, unblock, suspend, or delete users',
							'Reset access and review user activity',
							'Promote manual subscriptions for artists, DJs, and consumers',
						]}
					/>
					<ActionAreaCard
						title="Content Management"
						description="Moderate songs, videos, reels, and comments from one place."
						href="/admin/content"
						actions={[
							'View all songs and videos',
							'Delete, hide, or feature content',
							'Review reported content and abusive comments',
							'Open analytics for top-performing content',
						]}
					/>
					<ActionAreaCard
						title="Live Streaming & Battles"
						description="Monitor live streams and enforce safety during battles and sessions."
						href="/admin/live-streams"
						badge={snapshot.liveNow == null ? undefined : `${formatNumber(snapshot.liveNow)} live now`}
						actions={[
							'View all ongoing live streams',
							'End streams, cancel battles, and suspend hosts',
							'Mute or remove creators during unsafe activity',
							'Approve, cancel, schedule, and feature battles',
						]}
					/>
					<ActionAreaCard
						title="Subscriptions"
						description="Manage plan assignments manually for promotions, trials, and partnerships."
						href="/admin/subscriptions"
						badge={snapshot.activeSubscriptions == null ? undefined : `${formatNumber(snapshot.activeSubscriptions)} active`}
						actions={[
							'Subscribe artists, DJs, and consumers manually',
							'Cancel, remove, or extend subscriptions',
							'Use manual assignment tools for free trials and campaigns',
							'Monitor subscription payments and user subscriptions',
						]}
					/>
					<ActionAreaCard
						title="Coins & Payments"
						description="Control revenue, wallets, refunds, and supporter activity."
						href="/admin/payments"
						badge={snapshot.revenue30d == null ? undefined : formatMoneyMwk(snapshot.revenue30d)}
						actions={[
							'View coin purchases and payment history',
							'Refund coins, add coins, or remove coins',
							'Review top supporters and transaction logs',
							'Watch withdrawals, earnings, and finance tools',
						]}
					/>
					<ActionAreaCard
						title="Announcements, Promotions & Moderation"
						description="Push campaigns, platform messaging, and moderation outcomes."
						href="/admin/announcements"
						actions={[
							'Send announcements and push notifications',
							'Feature artists, songs, videos, and battles',
							'Review user reports and spam signals',
							'Warn, ignore, delete, or block from reports workflow',
						]}
					/>
				</div>
			</div>

			<div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 p-6">
				<div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
					<div>
						<h2 className="text-lg font-semibold text-white">2. What Admin should not do</h2>
						<p className="mt-1 text-sm text-zinc-300">These guardrails protect trust, platform integrity, and auditability.</p>
						<ul className="mt-4 space-y-2 text-sm text-zinc-300">
							<li>• Do not change user passwords without a real request.</li>
							<li>• Do not access private user messages.</li>
							<li>• Do not spend or transfer user coins for yourself.</li>
							<li>• Do not upload music pretending to be an artist or DJ.</li>
							<li>• Do not start battles or streams as a user.</li>
							<li>• Do not manipulate streaming or platform statistics.</li>
						</ul>
					</div>
					<div className="rounded-xl border border-white/10 bg-black/20 p-4 text-sm text-zinc-300 lg:max-w-sm">
						<div className="font-medium text-white">Bonus protection: Admin Logs</div>
						<p className="mt-2 text-zinc-400">
							Every sensitive action should remain traceable. The existing audit trail is available from the logs page.
						</p>
						<div className="mt-4 flex flex-wrap gap-2">
							<Link href="/admin/logs" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
								Open Admin Logs
							</Link>
							<Link href="/admin/analytics" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
								Open Analytics
							</Link>
						</div>
					</div>
				</div>
			</div>

			<div className="space-y-4">
				<div>
					<h2 className="text-lg font-semibold text-white">3. Recommended admin dashboard structure</h2>
					<p className="mt-1 text-sm text-zinc-400">Quick navigation groups aligned to the structure you proposed.</p>
				</div>
				<div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
					<MenuGroupCard title="Dashboard" href="/admin/dashboard" items={['Overview stats', 'Revenue snapshot', 'Live streams now']} />
					<MenuGroupCard title="Users" href="/admin/users" items={['Artists', 'DJs', 'Consumers', 'Blocked users']} />
					<MenuGroupCard title="Content" href="/admin/content" items={['Songs', 'Videos', 'Reported content', 'Moderation']} />
					<MenuGroupCard title="Live" href="/admin/live-streams" items={['Live streams', 'Battles', 'Scheduled battles']} />
					<MenuGroupCard title="Subscriptions" href="/admin/subscriptions" items={['Consumer subscriptions', 'Manual subscriptions', 'Plans', 'Payments']} />
					<MenuGroupCard title="Coins & Payments" href="/admin/payments" items={['Coin purchases', 'Refunds', 'User coins', 'Top supporters']} />
					<MenuGroupCard title="Notifications & Promotions" href="/admin/announcements" items={['Push notifications', 'Announcements', 'Featured artists', 'Featured songs']} />
					<MenuGroupCard title="Reports & Analytics" href="/admin/moderation/reports" items={['User reports', 'Content reports', 'Spam review', 'Admin logs']} />
				</div>
			</div>
		</div>
	)
}
