import { redirect } from 'next/navigation'
import { verifyFirebaseSessionCookie } from '@/lib/firebase/session'
import { LiveStreamsTable, type LiveStreamRow } from './LiveStreamsTable'
import { adminBackendFetchJson } from '@/lib/admin/backend'

export const runtime = 'nodejs'

type BackendStreamRow = {
	id: string
	channel_name: string
	streamer_name: string
	streamer_avatar_url: string | null
	host_type: 'dj' | 'artist'
	stream_type: 'dj_live' | 'artist_live' | 'battle'
	status: 'live' | 'ended'
	viewers: number
	started_at: string | null
	region: string
}

type SearchParams = { status?: string; region?: string }

function normalizeRegion(value: string | undefined): string {
	const v = (value ?? 'MW').trim().toUpperCase()
	return v || 'MW'
}

function normalizeStatus(value: string | undefined): 'live' | 'ended' | 'all' {
	const v = (value ?? 'live').trim().toLowerCase()
	if (v === 'ended') return 'ended'
	if (v === 'all') return 'all'
	return 'live'
}

export default async function LiveStreamsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
	const user = await verifyFirebaseSessionCookie()
	if (!user) redirect('/auth/login')

	const sp = await searchParams
	const region = normalizeRegion(sp.region)
	const status = normalizeStatus(sp.status)

	const [streams, activeStreams] = await Promise.all([
		adminBackendFetchJson<BackendStreamRow[]>(`/admin/streams?status=${encodeURIComponent(status)}&region=${encodeURIComponent(region)}&limit=250`).catch(() => []),
		adminBackendFetchJson<BackendStreamRow[]>('/admin/streams?status=live&limit=250').catch(() => []),
	])

	const rows: LiveStreamRow[] = streams.map((stream) => ({
		id: stream.id,
		channelName: String(stream.channel_name ?? ''),
		streamerName: String(stream.streamer_name ?? '—'),
		streamerAvatarUrl: stream.streamer_avatar_url ?? null,
		hostType: stream.host_type === 'artist' ? 'artist' : 'dj',
		streamType: stream.stream_type === 'battle' ? 'battle' : stream.stream_type === 'artist_live' ? 'artist_live' : 'dj_live',
		status: stream.status === 'ended' ? 'ended' : 'live',
		viewers: Number(stream.viewers ?? 0) || 0,
		startedAt: stream.started_at ?? null,
		region: String(stream.region ?? 'MW').toUpperCase(),
	}))

	const activeCount = activeStreams.length

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h1 className="text-lg font-semibold">Live Streaming Control</h1>
				<p className="mt-1 text-sm text-gray-400">Monitor all live sessions</p>
				<p className="mt-3 text-xs text-gray-400">Signed in as {user.email ?? user.uid}</p>
			</div>

			<LiveStreamsTable rows={rows} activeCount={activeCount} />
		</div>
	)
}
