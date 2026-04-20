import Link from 'next/link'

import { adminBackendFetchJson } from '@/lib/admin/backend'
import { getAdminContext } from '@/lib/admin/session'
import { FlagsTable, type FlagRow } from './FlagsTable'

export const runtime = 'nodejs'

export default async function ModerationFlagsPage(props: { searchParams: Promise<{ status?: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx || !ctx.permissions.can_stop_streams) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You do not have moderation permissions.</p>
				<div className="mt-4">
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back to moderation
					</Link>
				</div>
			</div>
		)
	}

	const sp = await props.searchParams
	const status = (sp.status ?? 'pending').toLowerCase()

	let rows: FlagRow[] = []
	let errorMessage: string | null = null
	try {
		rows = await adminBackendFetchJson<FlagRow[]>(`/admin/content/flags?limit=250${status !== 'all' ? `&status=${encodeURIComponent(status)}` : ''}`)
	} catch (error) {
		errorMessage = error instanceof Error ? error.message : 'Failed to load content flags'
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Content Flags</h1>
						<p className="mt-1 text-sm text-gray-400">Review and resolve moderation flags through the admin backend.</p>
					</div>
					<Link href="/admin/moderation" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>
				{errorMessage ? <p className="mt-4 text-sm text-red-400">Failed to load flags: {errorMessage}</p> : null}
			</div>
			<FlagsTable rows={rows} />
		</div>
	)
}