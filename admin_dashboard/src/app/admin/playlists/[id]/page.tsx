import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type PlaylistRow = {
	id: string
	title: string
	description: string | null
	country_code: string | null
	priority: number | null
	is_active: boolean
	starts_at: string | null
	ends_at: string | null
}

function isMissingTableError(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { code?: unknown; message?: unknown; details?: unknown; hint?: unknown }
	const code = typeof e.code === 'string' ? e.code : null
	if (code === '42P01' || code === 'PGRST205') return true
	const msg = [e.message, e.details, e.hint].map((x) => (typeof x === 'string' ? x : '')).join(' ').toLowerCase()
	return msg.includes('does not exist') || msg.includes('could not find the table')
}

export default async function PlaylistDetailPage(props: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const canManage =
		ctx.admin.role === 'super_admin' ||
		ctx.admin.role === 'operations_admin' ||
		ctx.permissions.can_manage_artists

	if (!canManage) redirect('/admin/playlists?error=forbidden')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return (
			<div className="space-y-6">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Playlist</h1>
					<p className="mt-1 text-sm text-gray-400">Service role required.</p>
				</div>
				<ServiceRoleRequired title="Service role required for playlists management" />
			</div>
		)
	}

	const { id } = await props.params
	let playlist: PlaylistRow | null = null
	let missing = false
	try {
		const { data, error } = await supabase
			.from('playlists')
			.select('id,title,description,country_code,priority,is_active,starts_at,ends_at')
			.eq('id', id)
			.limit(1)
			.maybeSingle()
		if (error) {
			if (isMissingTableError(error)) missing = true
			playlist = null
		} else {
			playlist = (data ?? null) as unknown as PlaylistRow | null
		}
	} catch (e) {
		missing = isMissingTableError(e)
		playlist = null
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Playlist</h1>
						<p className="mt-1 text-sm text-gray-400">Edit playlist metadata and manage items (coming next).</p>
					</div>
					<div className="flex gap-2">
						<Link href="/admin/playlists" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Back</Link>
					</div>
				</div>
			</div>

			{missing ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					<p className="font-semibold">Database table not found</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Run migration <span className="font-mono">supabase/migrations/20260202103000_playlists.sql</span>
					</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Then reload the schema cache (SQL: <span className="font-mono">NOTIFY pgrst, &apos;reload schema&apos;;</span>).
					</p>
				</div>
			) : null}

			{playlist ? (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<div className="grid gap-3 text-sm">
						<Row label="Title" value={playlist.title} />
						<Row label="Country" value={playlist.country_code ?? '—'} />
						<Row label="Priority" value={String(playlist.priority ?? 0)} />
						<Row label="Status" value={playlist.is_active ? 'Active' : 'Inactive'} />
						<Row label="Schedule" value={playlist.starts_at || playlist.ends_at ? `${playlist.starts_at ?? '…'} → ${playlist.ends_at ?? '…'}` : 'Always'} />
						{playlist.description ? <Row label="Description" value={playlist.description} /> : null}
					</div>
					<div className="mt-4 text-xs text-gray-500">Next: add playlist items UI (tracks/videos) once we confirm your content table IDs.</div>
				</div>
			) : (
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6 text-sm text-gray-400">Playlist not found.</div>
			)}
		</div>
	)
}

function Row(props: { label: string; value: string }) {
	return (
		<div className="flex items-center justify-between gap-4 border-b border-white/5 pb-2">
			<div className="text-gray-400">{props.label}</div>
			<div className="text-gray-200">{props.value}</div>
		</div>
	)
}
