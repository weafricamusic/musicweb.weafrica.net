import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type ReportRow = {
	id: string
	target_type: string
	target_id: string
	status: string
	reviewed_at?: string | null
	created_at: string
}

type FlagRow = {
	id: string
	content_type: string
	content_id: string
	status: string
	created_at: string
}

function StatCard({ label, value, href }: { label: string; value: string; href: string }) {
	return (
		<Link
			href={href}
			className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:bg-white/10 transition"
		>
			<p className="text-xs text-gray-400">{label}</p>
			<p className="mt-2 text-2xl font-semibold">{value}</p>
		</Link>
	)
}

export default async function ModerationOverviewPage() {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	let summaryError: string | null = null
	let openReports: ReportRow[] = []
	let reviewedReports: ReportRow[] = []
	let pendingFlags: FlagRow[] = []
	try {
		;[openReports, reviewedReports, pendingFlags] = await Promise.all([
			adminBackendFetchJson<ReportRow[]>('/admin/reports?status=pending&limit=250'),
			adminBackendFetchJson<ReportRow[]>('/admin/reports?status=reviewed&limit=250'),
			adminBackendFetchJson<FlagRow[]>('/admin/content/flags?status=pending&limit=250'),
		])
	} catch (error) {
		summaryError = error instanceof Error ? error.message : 'Failed to load moderation summary.'
	}

	const today = new Date().toISOString().slice(0, 10)
	const open = String(openReports.length)
	const resolvedToday = String(
		reviewedReports.filter((report) => String(report.reviewed_at ?? '').slice(0, 10) === today).length,
	)
	const blockedContent = String(pendingFlags.length)
	const blockedUsers = '—'
	const liveOpen = String(openReports.filter((report) => String(report.target_type).toLowerCase() === 'live').length)

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Moderation & Safety</h1>
						<p className="mt-1 text-sm text-gray-400">Protect brand, stop abuse, keep full history.</p>
					</div>
					<div className="flex gap-2">
						<Link href="/admin/moderation/reports" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							View reports
						</Link>
						<Link href="/admin/moderation/rules" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							Safety rules
						</Link>
					</div>
				</div>

				{summaryError ? (
					<div className="mt-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
						<b>Action needed:</b> moderation summary is currently unavailable from the admin backend. Error: {summaryError}
					</div>
				) : null}
			</div>

			<div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
				<StatCard label="Open Reports" value={open} href="/admin/moderation/reports?status=open" />
				<StatCard label="Reviewed Today" value={resolvedToday} href="/admin/moderation/reports?status=resolved" />
				<StatCard label="Pending Flags" value={blockedContent} href="/admin/moderation/flags?status=pending" />
				<StatCard label="Blocked Users (Today)" value={blockedUsers} href="/admin/moderation/users" />
			</div>

			<div className="grid gap-4 md:grid-cols-3">
				<Link href="/admin/moderation/flags" className="rounded-2xl border border-white/10 bg-white/5 p-6 hover:bg-white/10 transition">
					<p className="text-sm font-semibold">Content Flags</p>
					<p className="mt-1 text-sm text-gray-400">Resolve automated and manual moderation flags.</p>
				</Link>
				<Link href="/admin/moderation/lives" className="rounded-2xl border border-white/10 bg-white/5 p-6 hover:bg-white/10 transition">
					<p className="text-sm font-semibold">Live Stream Violations</p>
					<p className="mt-1 text-sm text-gray-400">Highest priority. Open live reports: {liveOpen}</p>
				</Link>
				<Link href="/admin/moderation/logs" className="rounded-2xl border border-white/10 bg-white/5 p-6 hover:bg-white/10 transition">
					<p className="text-sm font-semibold">Moderation Action Logs</p>
					<p className="mt-1 text-sm text-gray-400">Legal shield: every action recorded.</p>
				</Link>
			</div>
		</div>
	)
}
