import { redirect } from 'next/navigation'
import Link from 'next/link'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { DashboardShell } from '@/components/DashboardShell'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { StatCard } from '@/components/StatCard'
export const runtime = 'nodejs'

function formatNumber(value: number | null): string {
	if (value == null) return '—'
	return new Intl.NumberFormat(undefined).format(value)
}

type CountResult = { value: number | null; error?: string }

async function safeCount(
	supabase: ReturnType<typeof createSupabaseServerClient>,
	table: string,
	where?: (q: any) => any,
): Promise<CountResult> {
	try {
		let q = supabase.from(table).select('*', { head: true, count: 'exact' })
		if (where) q = where(q)
		const { count, error } = await q
		if (error) return { value: null, error: error.message }
		return { value: count ?? 0 }
	} catch (e) {
		return { value: null, error: e instanceof Error ? e.message : 'Unknown error' }
	}
}

type FeedItem = { ts: number; label: string; href: string }

async function safeRecentActivity(supabase: ReturnType<typeof createSupabaseServerClient>): Promise<FeedItem[]> {
	const [artists, djs, songs] = await Promise.all([
		(async () => {
			try {
				const { data, error } = await supabase
					.from('artists')
					.select('id,stage_name,name,created_at')
					.order('created_at', { ascending: false })
					.limit(5)
				if (error) return []
				return (data ?? []).map((a: any) => ({
					ts: a.created_at ? Date.parse(a.created_at) : 0,
					label: `New artist: ${a.stage_name ?? a.name ?? a.id}`,
					href: `/dashboard/artists/${encodeURIComponent(String(a.id))}`,
				})) as FeedItem[]
			} catch {
				return []
			}
		})(),
		(async () => {
			try {
				const { data, error } = await supabase
					.from('djs')
					.select('id,dj_name,created_at')
					.order('created_at', { ascending: false })
					.limit(5)
				if (error) return []
				return (data ?? []).map((d: any) => ({
					ts: d.created_at ? Date.parse(d.created_at) : 0,
					label: `New DJ: ${d.dj_name ?? d.id}`,
					href: `/dashboard/djs/${encodeURIComponent(String(d.id))}`,
				})) as FeedItem[]
			} catch {
				return []
			}
		})(),
		(async () => {
			try {
				const { data, error } = await supabase
					.from('songs')
					.select('id,title,created_at')
					.order('created_at', { ascending: false })
					.limit(5)
				if (error) return []
				return (data ?? []).map((s: any) => ({
					ts: s.created_at ? Date.parse(s.created_at) : 0,
					label: `Song uploaded: ${s.title ?? s.id}`,
					href: '/admin/moderation',
				})) as FeedItem[]
			} catch {
				return []
			}
		})(),
	])

	return [...artists, ...djs, ...songs]
		.filter((i) => i.ts > 0)
		.sort((a, b) => b.ts - a.ts)
		.slice(0, 10)
}

export default async function DashboardPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) {
		redirect('/auth/login')
	}

	const supabase = createSupabaseServerClient()
	const now = new Date()
	const startOfDay = new Date(now)
	startOfDay.setHours(0, 0, 0, 0)
	const startIso = startOfDay.toISOString()

	const [
		usersCount,
		approvedArtistsCount,
		approvedDjsCount,
		songsActiveCount,
		liveNowCount,
		todaySignupsCount,
		recent,
	] = await Promise.all([
		safeCount(supabase, 'users'),
		safeCount(supabase, 'artists', (q) => q.eq('approved', true)),
		safeCount(supabase, 'djs', (q) => q.eq('approved', true)),
		safeCount(supabase, 'songs', (q) => q.eq('is_active', true)),
		// Live is not wired to Agora yet. Try common table names; if missing, show "—".
		(async () => {
			const a = await safeCount(supabase, 'live_streams', (q) => q.eq('status', 'live'))
			if (a.value != null || !a.error) return a
			return safeCount(supabase, 'lives', (q) => q.eq('is_live', true))
		})(),
		safeCount(supabase, 'users', (q) => q.gte('created_at', startIso)),
		safeRecentActivity(supabase),
	])

	return (
		<DashboardShell title="Dashboard Overview">
			<div className="space-y-8">
				<section className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
						<div>
							<h2 className="text-lg font-semibold">Dashboard Overview</h2>
							<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Welcome back, Admin</p>
						</div>
						<div className="flex flex-wrap items-center gap-2">
							<span className="rounded-full border border-black/[.08] px-3 py-1 text-xs text-zinc-700 dark:border-white/[.145] dark:text-zinc-200">
								{now.toLocaleString()}
							</span>
							<span className="rounded-full border border-black/[.08] px-3 py-1 text-xs text-zinc-700 dark:border-white/[.145] dark:text-zinc-200">
								Malawi (Primary Market)
							</span>
						</div>
					</div>
					<p className="mt-4 text-xs text-zinc-600 dark:text-zinc-400">Signed in as {user.email ?? user.uid}</p>
				</section>

				<section>
					<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
						<StatCard title="Total Users" value={`${formatNumber(usersCount.value)} Users`} href="/dashboard/users" />
						<StatCard
							title="Total Artists"
							value={formatNumber(approvedArtistsCount.value)}
							sub="Approved only"
							href="/dashboard/artists"
						/>
						<StatCard
							title="Total DJs"
							value={formatNumber(approvedDjsCount.value)}
							sub="Approved only"
							href="/dashboard/djs"
						/>
						<StatCard
							title="Total Songs"
							value={formatNumber(songsActiveCount.value)}
							sub="Active only"
							href="/admin/moderation"
						/>
						<StatCard
							title="Live Streams"
							value={formatNumber(liveNowCount.value)}
							sub="Live now"
							href="/admin/dashboard"
						/>
						<StatCard
							title="Today’s Activity"
							value={todaySignupsCount.value == null ? '—' : `+${formatNumber(todaySignupsCount.value)} Today`}
							sub="New signups"
							href="/dashboard/users"
						/>
					</div>
				</section>

				<section className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<h3 className="text-base font-semibold">Quick Actions</h3>
					<div className="mt-4 flex flex-wrap gap-2">
						<Link
							href="/admin/artists"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							Approve New Artist
						</Link>
						<Link
							href="/admin/djs"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							Approve New DJ
						</Link>
						<Link
							href="/admin/dashboard"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							View Live Streams
						</Link>
						<Link
							href="/dashboard/users"
							className="inline-flex h-10 items-center rounded-xl border border-black/[.08] px-4 text-sm dark:border-white/[.145]"
						>
							Review Blocked Users
						</Link>
					</div>
				</section>

				<section className="rounded-2xl border border-black/[.08] bg-white p-6 dark:border-white/[.145] dark:bg-black">
					<h3 className="text-base font-semibold">Recent Activity</h3>
					<p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">Latest 10 activity entries (visibility only).</p>
					<div className="mt-4 space-y-2 text-sm">
						{recent.length ? (
							recent.map((item) => (
								<div key={item.ts + item.href} className="flex items-start justify-between gap-3">
									<Link href={item.href} className="hover:underline">
										{item.label}
									</Link>
									<span className="shrink-0 text-xs text-zinc-600 dark:text-zinc-400">
										{new Date(item.ts).toLocaleString()}
									</span>
								</div>
							))
						) : (
							<p className="text-sm text-zinc-600 dark:text-zinc-400">No recent activity available yet.</p>
						)}
					</div>
				</section>
			</div>
		</DashboardShell>
	)
}
