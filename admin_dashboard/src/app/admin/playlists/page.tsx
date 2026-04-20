import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'
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
	created_at: string
	updated_at: string
}

function asString(v: unknown): string {
	return typeof v === 'string' ? v : String(v ?? '')
}

function isMissingTableError(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { code?: unknown; message?: unknown; details?: unknown; hint?: unknown }
	const code = typeof e.code === 'string' ? e.code : null
	if (code === '42P01' || code === 'PGRST205') return true
	const msg = [e.message, e.details, e.hint].map((x) => (typeof x === 'string' ? x : '')).join(' ').toLowerCase()
	return msg.includes('does not exist') || msg.includes('could not find the table')
}

function normalizeText(raw: FormDataEntryValue | null, maxLen: number): string {
	const v = typeof raw === 'string' ? raw.trim() : ''
	return v.slice(0, maxLen)
}

async function loadPlaylists(): Promise<{ rows: PlaylistRow[]; missing: boolean }> {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return { rows: [], missing: false }
	try {
		const { data, error } = await supabase
			.from('playlists')
			.select('id,title,description,country_code,priority,is_active,starts_at,ends_at,created_at,updated_at')
			.order('is_active', { ascending: false })
			.order('priority', { ascending: false })
			.order('created_at', { ascending: false })
			.limit(250)
		if (error) {
			if (isMissingTableError(error)) return { rows: [], missing: true }
			return { rows: [], missing: false }
		}
		return { rows: (data ?? []) as unknown as PlaylistRow[], missing: false }
	} catch (e) {
		if (isMissingTableError(e)) return { rows: [], missing: true }
		return { rows: [], missing: false }
	}
}

export default async function PlaylistsPage(props: { searchParams?: Promise<{ ok?: string; error?: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	const canManage =
		ctx.admin.role === 'super_admin' ||
		ctx.admin.role === 'operations_admin' ||
		ctx.permissions.can_manage_artists

	if (!canManage) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You don’t have permission to manage playlists.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
				</div>
			</div>
		)
	}

	const sp = (props.searchParams ? await props.searchParams : {}) ?? {}
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return (
			<div className="space-y-6">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
					<h1 className="text-lg font-semibold">Playlists</h1>
					<p className="mt-1 text-sm text-gray-400">Curate featured playlists and manage visibility.</p>
				</div>
				<ServiceRoleRequired title="Service role required for playlists management" />
			</div>
		)
	}

	const playlistsRes = await loadPlaylists()

	async function createPlaylist(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const canManage =
			ctx.admin.role === 'super_admin' ||
			ctx.admin.role === 'operations_admin' ||
			ctx.permissions.can_manage_artists
		if (!canManage) redirect('/admin/playlists?error=forbidden')

		const title = normalizeText(formData.get('title'), 120)
		const country = normalizeText(formData.get('country_code'), 2).toUpperCase()
		const priorityRaw = normalizeText(formData.get('priority'), 16)
		const priority = priorityRaw ? Number(priorityRaw) : 0
		if (!title) redirect('/admin/playlists?error=missing_title')
		if (country && !/^[A-Z]{2}$/.test(country)) redirect('/admin/playlists?error=invalid_country')
		if (!Number.isFinite(priority)) redirect('/admin/playlists?error=invalid_priority')

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/playlists?error=service_role_required')

		try {
			const { data, error } = await supabaseAdmin
				.from('playlists')
				.insert({ title, country_code: country || null, priority, is_active: true })
				.select('id,title,is_active,priority,country_code')
				.limit(1)
				.single()
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'playlists.create',
				target_type: 'playlist',
				target_id: data.id,
				before_state: null,
				after_state: data as unknown as Record<string, unknown>,
				meta: { module: 'playlists' },
			})

			redirect('/admin/playlists?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'create_failed'
			redirect(`/admin/playlists?error=${encodeURIComponent(msg)}`)
		}
	}

	async function setActive(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const canManage =
			ctx.admin.role === 'super_admin' ||
			ctx.admin.role === 'operations_admin' ||
			ctx.permissions.can_manage_artists
		if (!canManage) redirect('/admin/playlists?error=forbidden')

		const id = asString(formData.get('id')).trim()
		const nextRaw = asString(formData.get('next')).trim()
		if (!id) redirect('/admin/playlists?error=missing_id')
		if (!(nextRaw === 'true' || nextRaw === 'false')) redirect('/admin/playlists?error=invalid_value')
		const nextVal = nextRaw === 'true'

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/playlists?error=service_role_required')

		let before: Record<string, unknown> | null = null
		try {
			const { data } = await supabaseAdmin.from('playlists').select('title,is_active').eq('id', id).limit(1).maybeSingle()
			before = (data ?? null) as unknown as Record<string, unknown> | null
		} catch {
			before = null
		}

		try {
			const { error } = await supabaseAdmin.from('playlists').update({ is_active: nextVal }).eq('id', id)
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'playlists.set_active',
				target_type: 'playlist',
				target_id: id,
				before_state: before,
				after_state: { is_active: nextVal },
				meta: { module: 'playlists' },
			})

			redirect('/admin/playlists?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'update_failed'
			redirect(`/admin/playlists?error=${encodeURIComponent(msg)}`)
		}
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Playlists</h1>
						<p className="mt-1 text-sm text-gray-400">Curate featured playlists and manage visibility.</p>
						<p className="mt-3 text-xs text-gray-500">Create playlists here; items can be added in a follow-up step.</p>
					</div>
					<div className="flex gap-2">
						<a href="/api/admin/playlists" target="_blank" rel="noreferrer" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">API preview</a>
						<Link href="/admin/content/promotions" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Promotions</Link>
					</div>
				</div>
			</div>

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved.</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{sp.error}</div>
			) : null}

			{playlistsRes.missing ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					<p className="font-semibold">Database table not found</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Create it by running the migration: <span className="font-mono">supabase/migrations/20260202103000_playlists.sql</span>
					</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Then reload the schema cache (SQL: <span className="font-mono">NOTIFY pgrst, &apos;reload schema&apos;;</span>).
					</p>
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h2 className="text-base font-semibold">Create Playlist</h2>
						<p className="mt-1 text-xs text-gray-400">Optional country code allows market-specific playlists.</p>
					</div>
					<form action={createPlaylist} className="flex flex-wrap items-center justify-end gap-2">
						<input
							name="title"
							placeholder="Playlist title"
							className="h-10 w-56 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none placeholder:text-gray-500 focus:border-white/20"
						/>
						<input
							name="country_code"
							placeholder="Country (MW)"
							className="h-10 w-28 rounded-xl border border-white/10 bg-black/20 px-3 text-sm uppercase outline-none placeholder:text-gray-500 focus:border-white/20"
						/>
						<input
							name="priority"
							placeholder="Priority"
							defaultValue={0}
							className="h-10 w-28 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none placeholder:text-gray-500 focus:border-white/20"
						/>
						<button className="inline-flex h-10 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-sm hover:bg-white/10">Add</button>
					</form>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 overflow-auto">
				<div className="flex items-center justify-between gap-4">
					<div>
						<h2 className="text-base font-semibold">All Playlists</h2>
						<p className="mt-1 text-sm text-gray-400">{playlistsRes.rows.length} playlists</p>
					</div>
				</div>

				<table className="mt-4 w-full min-w-[900px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Title</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Priority</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Schedule</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{playlistsRes.rows.map((p) => (
							<tr key={p.id} className="text-gray-200">
								<td className="border-b border-white/5 py-3 pr-4">
									<div className="flex items-center gap-2">
										<Link href={`/admin/playlists/${encodeURIComponent(p.id)}`} className="font-semibold hover:underline">{p.title}</Link>
										{p.description ? <span className="text-xs text-gray-500 line-clamp-1">{p.description}</span> : null}
									</div>
								</td>
								<td className="border-b border-white/5 py-3 pr-4 text-gray-300">{p.country_code ?? '—'}</td>
								<td className="border-b border-white/5 py-3 pr-4 text-gray-300">{String(p.priority ?? 0)}</td>
								<td className="border-b border-white/5 py-3 pr-4 text-gray-300">
									{p.starts_at || p.ends_at ? (
										<span className="text-xs">{p.starts_at ?? '…'} → {p.ends_at ?? '…'}</span>
									) : (
										<span className="text-xs text-gray-500">Always</span>
									)}
								</td>
								<td className="border-b border-white/5 py-3 pr-4">
									{p.is_active ? (
										<span className="rounded-full bg-emerald-500/15 px-2 py-1 text-xs text-emerald-200">Active</span>
									) : (
										<span className="rounded-full bg-gray-500/15 px-2 py-1 text-xs text-gray-300">Inactive</span>
									)}
								</td>
								<td className="border-b border-white/5 py-3 pr-4">
									<form action={setActive} className="inline-flex">
										<input type="hidden" name="id" value={p.id} />
										<input type="hidden" name="next" value={p.is_active ? 'false' : 'true'} />
										<button className="inline-flex h-9 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-xs hover:bg-white/10">
											{p.is_active ? 'Deactivate' : 'Activate'}
										</button>
									</form>
								</td>
							</tr>
						))}
						{playlistsRes.rows.length === 0 ? (
							<tr>
								<td colSpan={6} className="py-8 text-center text-sm text-gray-500">No playlists yet.</td>
							</tr>
						) : null}
					</tbody>
				</table>
			</div>
		</div>
	)
}
