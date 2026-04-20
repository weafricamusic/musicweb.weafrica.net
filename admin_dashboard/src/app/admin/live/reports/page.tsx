import Link from 'next/link'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export default async function LiveReportsPage() {
	return (
		<div className="mx-auto max-w-2xl space-y-4">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-xl font-semibold">Live Reports</h1>
				<p className="mt-2 text-sm text-gray-400">Reports related to live sessions and battles.</p>
				<div className="mt-5 flex flex-wrap gap-2">
					<Link href="/admin/live-streams" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Ongoing Live Sessions
					</Link>
					<Link href="/admin/moderation/lives" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Legacy Live Moderation Reports
					</Link>
				</div>
			</div>
		</div>
	)
}
