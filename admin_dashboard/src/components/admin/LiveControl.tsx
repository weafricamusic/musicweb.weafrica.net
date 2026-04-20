import type { ReactNode } from 'react'
import Link from 'next/link'
import { createSupabaseServerClient } from '@/lib/supabase/server'

export default async function LiveControl() {
	const supabase = createSupabaseServerClient()
	let rows: Array<{ id: string; channel_name: string; viewer_count: number | null }> = []
	let activeCount: number | null = null
	type LiveStreamQueryRow = { id: string; channel_name: string; viewer_count: number | null; status: string; started_at: string | null }

	try {
		const { data } = await supabase
			.from('live_streams')
			.select('id,channel_name,viewer_count,status,started_at')
			.eq('status', 'live')
			.order('started_at', { ascending: false })
			.limit(5)
		rows = ((data ?? []) as LiveStreamQueryRow[]).map((r) => ({
			id: r.id,
			channel_name: r.channel_name,
			viewer_count: r.viewer_count,
		}))
		activeCount = rows.length
	} catch {
		rows = []
		activeCount = null
	}

	return (
		<Card title="Live Control Panel">
			<div className="flex items-start justify-between gap-3">
				<div>
					<p className="text-sm text-gray-400">Active live count</p>
					<p className="mt-1 text-lg font-semibold">{activeCount == null ? '—' : activeCount}</p>
				</div>
				<Link href="/admin/live-streams" className="text-sm underline text-gray-200 hover:text-white">
					Open Live Streams
				</Link>
			</div>

			<TableHeader />

			{rows.length ? (
				rows.map((r) => (
					<div key={r.id} className="flex justify-between items-center py-3 border-t border-white/10">
						<div className="min-w-0">
							<p className="truncate">{r.channel_name}</p>
							<p className="truncate text-xs text-gray-400">Stream ID: {r.id}</p>
						</div>
						<span className="text-gray-400">{Number(r.viewer_count ?? 0) || 0}</span>
						<Link
							href={`/admin/live-streams/${encodeURIComponent(String(r.id))}`}
							className="bg-white/10 px-3 py-1 rounded text-sm hover:bg-white/15"
						>
							View
						</Link>
					</div>
				))
			) : (
				<p className="mt-3 text-sm text-gray-400">No active streams right now.</p>
			)}
		</Card>
	)
}

function TableHeader() {
	return (
		<div className="flex justify-between text-sm text-gray-400 pb-2">
			<span>Channel</span>
			<span>Viewers</span>
			<span>Actions</span>
		</div>
	)
}

function Card({ title, children }: { title: string; children: ReactNode }) {
	return (
		<div className="bg-white/5 rounded-xl p-5">
			<h2 className="font-semibold mb-4">{title}</h2>
			{children}
		</div>
	)
}
