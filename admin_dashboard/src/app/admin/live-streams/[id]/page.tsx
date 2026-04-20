import Link from 'next/link'
import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { StreamActions } from './StreamActions'

export const runtime = 'nodejs'

type BackendStreamDetail = {
	id: string
	channel_name: string
	streamer_name: string
	status: 'live' | 'ended'
	viewers: number
	started_at: string | null
	ended_at: string | null
	region: string
	title: string | null
	category: string | null
	topic: string | null
	access_mode: string | null
}

export default async function LiveStreamDetailPage({ params }: { params: Promise<{ id: string }> }) {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const { id } = await params
	if (!id) redirect('/admin/live-streams')

	const stream = await adminBackendFetchJson<BackendStreamDetail | null>(`/admin/streams/${encodeURIComponent(id)}`).catch(() => null)
	if (!stream) {
		return (
			<div className="space-y-6">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Live stream</h1>
					<p className="mt-2 text-sm text-red-400">Failed to load stream: Not found</p>
					<Link href="/admin/live-streams" className="mt-4 inline-flex text-sm underline">
						Back
					</Link>
				</div>
			</div>
		)
	}

	const status = stream.status === 'ended' ? 'ended' : 'live'
	const startedAt = stream.started_at ? new Date(String(stream.started_at)).toLocaleString() : '—'
	const endedAt = stream.ended_at ? new Date(String(stream.ended_at)).toLocaleString() : null

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for live stream monitoring" />

	// Best-effort monitoring placeholders (tables may not exist yet)
	let chat: any[] = []
	let gifts: any[] = []
	try {
		const { data } = await supabase
			.from('live_stream_chat_messages')
			.select('*')
			.eq('stream_id', id)
			.order('created_at', { ascending: false })
			.limit(50)
		chat = (data ?? []) as any[]
	} catch {
		chat = []
	}

	try {
		const { data } = await supabase
			.from('live_stream_gifts')
			.select('*')
			.eq('stream_id', id)
			.order('created_at', { ascending: false })
			.limit(50)
		gifts = (data ?? []) as any[]
	} catch {
		gifts = []
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">View Live Stream (Admin Mode)</h1>
						<p className="mt-1 text-sm text-gray-400">Read-only monitoring</p>
					</div>
					<Link href="/admin/live-streams" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Back
					</Link>
				</div>

				<div className="mt-4 grid gap-3 text-sm md:grid-cols-2">
					<div>
						<p className="text-gray-400">Channel</p>
						<p className="mt-1 break-all">{String(stream.channel_name ?? '—')}</p>
					</div>
					<div>
						<p className="text-gray-400">Status</p>
						<p className="mt-1">{status === 'live' ? 'Live' : 'Ended'}</p>
					</div>
					<div>
						<p className="text-gray-400">Streamer</p>
						<p className="mt-1">{String(stream.streamer_name ?? '—')}</p>
					</div>
					<div>
						<p className="text-gray-400">Viewers</p>
						<p className="mt-1">{Number(stream.viewers ?? 0) || 0}</p>
					</div>
					<div>
						<p className="text-gray-400">Region</p>
						<p className="mt-1">{String(stream.region ?? 'MW').toUpperCase()}</p>
					</div>
					<div>
						<p className="text-gray-400">Title</p>
						<p className="mt-1">{String(stream.title ?? '—')}</p>
					</div>
					<div>
						<p className="text-gray-400">Category</p>
						<p className="mt-1">{String(stream.category ?? stream.topic ?? '—')}</p>
					</div>
					<div>
						<p className="text-gray-400">Access</p>
						<p className="mt-1">{String(stream.access_mode ?? 'public')}</p>
					</div>
					<div>
						<p className="text-gray-400">Started</p>
						<p className="mt-1">{startedAt}</p>
					</div>
					<div>
						<p className="text-gray-400">Ended</p>
						<p className="mt-1">{endedAt ?? '—'}</p>
					</div>
				</div>
			</div>

			<div className="grid gap-6 lg:grid-cols-2">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h3 className="text-base font-semibold">Video</h3>
					<p className="mt-2 text-sm text-gray-400">
						Video player integration is not wired in this admin app yet. This view is intended for monitoring.
					</p>
					<div className="mt-4 flex h-64 items-center justify-center rounded-xl border border-white/10 bg-black/20 text-sm text-gray-400">
						Stream preview placeholder
					</div>
				</div>

				<div className="space-y-6">
					<StreamActions id={String(stream.id)} status={status} />
					<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
						<h3 className="text-base font-semibold">Chat (monitor only)</h3>
						<p className="mt-1 text-sm text-gray-400">Admin cannot chat.</p>
						{chat.length ? (
							<div className="mt-4 space-y-2 text-sm">
								{chat.map((m, idx) => (
									<div key={idx} className="rounded-xl border border-white/10 bg-black/20 p-3">
										<p className="text-xs text-gray-400">{String(m.created_at ?? '')}</p>
										<p className="mt-1 break-words">{String(m.text ?? m.message ?? '')}</p>
									</div>
								))}
							</div>
						) : (
							<p className="mt-4 text-sm text-gray-400">No chat data available (table not wired yet).</p>
						)}
					</div>

					<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
						<h3 className="text-base font-semibold">Gifts / Coins (monitor only)</h3>
						<p className="mt-1 text-sm text-gray-400">Admin cannot send gifts.</p>
						{gifts.length ? (
							<div className="mt-4 space-y-2 text-sm">
								{gifts.map((g, idx) => (
									<div key={idx} className="rounded-xl border border-white/10 bg-black/20 p-3">
										<p className="text-xs text-gray-400">{String(g.created_at ?? '')}</p>
										<p className="mt-1 break-words">{JSON.stringify(g)}</p>
									</div>
								))}
							</div>
						) : (
							<p className="mt-4 text-sm text-gray-400">No gift/coin data available (table not wired yet).</p>
						)}
					</div>
				</div>
			</div>
		</div>
	)
}
