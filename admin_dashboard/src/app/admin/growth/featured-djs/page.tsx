import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export default async function FeaturedDJsPage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-lg font-semibold">Featured DJs</h1>
				<p className="mt-1 text-sm text-gray-400">This section is scaffolded but not yet wired to storage.</p>
				<div className="mt-5 flex flex-wrap gap-2">
					<Link
						href="/admin/growth"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Back to Growth
					</Link>
					<Link
						href="/admin/dashboard"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Back to Overview
					</Link>
				</div>
			</div>
		</div>
	)
}
