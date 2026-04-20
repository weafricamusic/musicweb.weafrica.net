import Link from 'next/link'
import { getDjVerificationRows } from '../../actions'
import { DjVerificationTable } from '../../DjVerificationTable'
import type { VerificationBucket } from '../../actions'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function isBucket(input: string): input is VerificationBucket {
	return input === 'pending' || input === 'approved' || input === 'rejected'
}

export default async function DjVerificationBucketPage(props: { params: Promise<{ bucket: string }> }) {
	const { bucket } = await props.params
	if (!isBucket(bucket)) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Not found</h1>
				<p className="mt-2 text-sm text-gray-400">Unknown bucket.</p>
				<div className="mt-4">
					<Link
						href="/admin/verification"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Back to verification
					</Link>
				</div>
			</div>
		)
	}

	let rows: Awaited<ReturnType<typeof getDjVerificationRows>> = []
	let loadError: string | null = null
	try {
		rows = await getDjVerificationRows(bucket)
	} catch (e) {
		loadError = e instanceof Error ? e.message : 'Failed to load DJs'
	}

	return (
		<div className="space-y-4">
			<div className="flex flex-wrap gap-2">
				<Link href="/admin/verification" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Verification home
				</Link>
				<Link href="/admin/verification/djs/pending" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Pending
				</Link>
				<Link href="/admin/verification/djs/approved" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Approved
				</Link>
				<Link href="/admin/verification/djs/rejected" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
					Rejected
				</Link>
			</div>

			{loadError ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
					<div className="font-medium">DJ list unavailable</div>
					<div className="mt-1 opacity-90">{loadError}</div>
				</div>
			) : (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<DjVerificationTable rows={rows} />
				</div>
			)}
		</div>
	)
}
