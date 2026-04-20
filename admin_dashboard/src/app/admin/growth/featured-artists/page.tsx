import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import FeaturedArtistsSuggest from './FeaturedArtistsSuggest'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type FeaturedArtistRow = {
	id: string
	artist_id: string
	country_code: string | null
	priority: number | null
	is_active: boolean
	starts_at: string | null
	ends_at: string | null
	created_at: string
	updated_at: string
}

type ArtistLookupRow = {
	id: string
	stage_name: string | null
	name?: string | null
	display_name?: string | null
}

function asString(v: unknown): string {
	return typeof v === 'string' ? v : String(v ?? '')
}

function isMissingTableError(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const e = err as { code?: unknown; message?: unknown; details?: unknown; hint?: unknown }
	const code = typeof e.code === 'string' ? e.code : null
	if (code === '42P01' || code === 'PGRST205') return true
	const msg = [e.message, e.details, e.hint]
		.map((x) => (typeof x === 'string' ? x : ''))
		.join(' ')
		.toLowerCase()
	return msg.includes('does not exist') || msg.includes('could not find the table')
}

function normalizeText(raw: FormDataEntryValue | null, maxLen: number): string {
	const v = typeof raw === 'string' ? raw.trim() : ''
	return v.slice(0, maxLen)
}

async function loadFeaturedArtists(): Promise<{ rows: FeaturedArtistRow[]; missing: boolean }> {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return { rows: [], missing: false }

	try {
		const { data, error } = await supabase
			.from('featured_artists')
			.select('id,artist_id,country_code,priority,is_active,starts_at,ends_at,created_at,updated_at')
			.order('is_active', { ascending: false })
			.order('priority', { ascending: false })
			.order('created_at', { ascending: false })
			.limit(250)
		if (error) {
			if (isMissingTableError(error)) return { rows: [], missing: true }
			return { rows: [], missing: false }
		}
		return { rows: (data ?? []) as unknown as FeaturedArtistRow[], missing: false }
	} catch (e) {
		if (isMissingTableError(e)) return { rows: [], missing: true }
		return { rows: [], missing: false }
	}
}

async function loadArtistsById(ids: string[]): Promise<Map<string, ArtistLookupRow>> {
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return new Map()
	if (!ids.length) return new Map()

	const uniq = Array.from(new Set(ids)).filter(Boolean)
	if (!uniq.length) return new Map()

	const trySelect = async (columns: string) => {
		const { data, error } = await supabase.from('artists').select(columns).in('id', uniq).limit(uniq.length)
		if (error) throw error
		return (data ?? []) as unknown as ArtistLookupRow[]
	}

	let rows: ArtistLookupRow[] = []
	try {
		rows = await trySelect('id,stage_name,name,display_name')
	} catch {
		try {
			rows = await trySelect('id,stage_name')
		} catch {
			rows = uniq.map((id) => ({ id, stage_name: null }))
		}
	}

	return new Map(rows.map((r) => [r.id, r]))
}

export default async function FeaturedArtistsPage(props: {
	searchParams?: Promise<{ ok?: string; error?: string }>
}) {
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
				<p className="mt-2 text-sm text-gray-400">You don’t have permission to manage featured artists.</p>
				<div className="mt-4">
					<Link
						href="/admin/growth"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Back to Growth
					</Link>
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
					<h1 className="text-lg font-semibold">Featured Artists</h1>
					<p className="mt-1 text-sm text-gray-400">Curate artists highlighted in discovery surfaces.</p>
				</div>
				<ServiceRoleRequired title="Service role required for Featured Artists" />
			</div>
		)
	}

	const featuredRes = await loadFeaturedArtists()
	const artistsById = await loadArtistsById(featuredRes.rows.map((r) => r.artist_id))

	async function addFeatured(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const canManage =
			ctx.admin.role === 'super_admin' ||
			ctx.admin.role === 'operations_admin' ||
			ctx.permissions.can_manage_artists
		if (!canManage) redirect('/admin/growth/featured-artists?error=forbidden')

		const artistId = normalizeText(formData.get('artist_id'), 64)
		const country = normalizeText(formData.get('country_code'), 2).toUpperCase()
		const priorityRaw = normalizeText(formData.get('priority'), 16)
		const priority = priorityRaw ? Number(priorityRaw) : 0

		if (!artistId) redirect('/admin/growth/featured-artists?error=missing_artist_id')
		if (country && !/^[A-Z]{2}$/.test(country)) redirect('/admin/growth/featured-artists?error=invalid_country')
		if (!Number.isFinite(priority)) redirect('/admin/growth/featured-artists?error=invalid_priority')

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/growth/featured-artists?error=service_role_required')

		try {
			const { data, error } = await supabaseAdmin
				.from('featured_artists')
				.upsert(
					{ artist_id: artistId, country_code: country || null, priority, is_active: true },
					{ onConflict: 'artist_id' },
				)
				.select('id,artist_id,country_code,priority,is_active')
				.limit(1)
				.single()
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'growth.featured_artists.upsert',
				target_type: 'artist',
				target_id: artistId,
				before_state: null,
				after_state: data as unknown as Record<string, unknown>,
				meta: { module: 'growth', feature: 'featured_artists' },
			})

			redirect('/admin/growth/featured-artists?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'upsert_failed'
			redirect(`/admin/growth/featured-artists?error=${encodeURIComponent(msg)}`)
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
		if (!canManage) redirect('/admin/growth/featured-artists?error=forbidden')

		const id = asString(formData.get('id')).trim()
		const nextRaw = asString(formData.get('next')).trim()
		if (!id) redirect('/admin/growth/featured-artists?error=missing_id')
		if (!(nextRaw === 'true' || nextRaw === 'false')) redirect('/admin/growth/featured-artists?error=invalid_value')
		const nextVal = nextRaw === 'true'

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/growth/featured-artists?error=service_role_required')

		let before: Record<string, unknown> | null = null
		try {
			const { data } = await supabaseAdmin
				.from('featured_artists')
				.select('artist_id,is_active')
				.eq('id', id)
				.limit(1)
				.maybeSingle()
			before = (data ?? null) as unknown as Record<string, unknown> | null
		} catch {
			before = null
		}

		try {
			const { error } = await supabaseAdmin.from('featured_artists').update({ is_active: nextVal }).eq('id', id)
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'growth.featured_artists.set_active',
				target_type: 'featured_artist',
				target_id: id,
				before_state: before,
				after_state: { is_active: nextVal },
				meta: { module: 'growth', feature: 'featured_artists' },
			})

			redirect('/admin/growth/featured-artists?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'update_failed'
			redirect(`/admin/growth/featured-artists?error=${encodeURIComponent(msg)}`)
		}
	}

	async function setPriority(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const canManage =
			ctx.admin.role === 'super_admin' ||
			ctx.admin.role === 'operations_admin' ||
			ctx.permissions.can_manage_artists
		if (!canManage) redirect('/admin/growth/featured-artists?error=forbidden')

		const id = asString(formData.get('id')).trim()
		const priorityRaw = normalizeText(formData.get('priority'), 16)
		const priority = priorityRaw ? Number(priorityRaw) : 0
		if (!id) redirect('/admin/growth/featured-artists?error=missing_id')
		if (!Number.isFinite(priority)) redirect('/admin/growth/featured-artists?error=invalid_priority')

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/growth/featured-artists?error=service_role_required')

		let before: Record<string, unknown> | null = null
		try {
			const { data } = await supabaseAdmin.from('featured_artists').select('artist_id,priority').eq('id', id).limit(1).maybeSingle()
			before = (data ?? null) as unknown as Record<string, unknown> | null
		} catch {
			before = null
		}

		try {
			const { error } = await supabaseAdmin.from('featured_artists').update({ priority }).eq('id', id)
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'growth.featured_artists.set_priority',
				target_type: 'featured_artist',
				target_id: id,
				before_state: before,
				after_state: { priority },
				meta: { module: 'growth', feature: 'featured_artists' },
			})

			redirect('/admin/growth/featured-artists?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'update_failed'
			redirect(`/admin/growth/featured-artists?error=${encodeURIComponent(msg)}`)
		}
	}

	async function removeFeatured(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')
		const canManage =
			ctx.admin.role === 'super_admin' ||
			ctx.admin.role === 'operations_admin' ||
			ctx.permissions.can_manage_artists
		if (!canManage) redirect('/admin/growth/featured-artists?error=forbidden')

		const id = asString(formData.get('id')).trim()
		if (!id) redirect('/admin/growth/featured-artists?error=missing_id')

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/growth/featured-artists?error=service_role_required')

		let before: Record<string, unknown> | null = null
		try {
			const { data } = await supabaseAdmin
				.from('featured_artists')
				.select('artist_id,country_code,priority,is_active')
				.eq('id', id)
				.limit(1)
				.maybeSingle()
			before = (data ?? null) as unknown as Record<string, unknown> | null
		} catch {
			before = null
		}

		try {
			const { error } = await supabaseAdmin.from('featured_artists').delete().eq('id', id)
			if (error) throw error

			await logAdminAction({
				ctx,
				action: 'growth.featured_artists.delete',
				target_type: 'featured_artist',
				target_id: id,
				before_state: before,
				after_state: null,
				meta: { module: 'growth', feature: 'featured_artists' },
			})

			redirect('/admin/growth/featured-artists?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'delete_failed'
			redirect(`/admin/growth/featured-artists?error=${encodeURIComponent(msg)}`)
		}
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Featured Artists</h1>
						<p className="mt-1 text-sm text-gray-400">Curate artists highlighted in discovery surfaces.</p>
						<p className="mt-3 text-xs text-gray-500">
							Tip: copy an artist UUID from{' '}
							<Link className="underline" href="/admin/artists">
								Artists
							</Link>
							.
						</p>
					</div>
					<div className="flex gap-2">
						<a
							href="/api/admin/growth/featured-artists"
							target="_blank"
							rel="noreferrer"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							API preview
						</a>
						<Link
							href="/admin/growth"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Back to Growth
						</Link>
					</div>
				</div>
			</div>

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved.</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{sp.error}</div>
			) : null}

			{featuredRes.missing ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					<p className="font-semibold">Database table not found</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Create it by running the migration:{' '}
						<span className="font-mono">supabase/migrations/20260202120000_featured_artists.sql</span>
					</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Then reload the schema cache (SQL: <span className="font-mono">NOTIFY pgrst, &apos;reload schema&apos;;</span>).
					</p>
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h2 className="text-base font-semibold">Add Featured Artist</h2>
						<p className="mt-1 text-xs text-gray-400">Featured entries are ordered by priority, then recency.</p>
					</div>
					<form action={addFeatured} className="flex flex-wrap items-center justify-end gap-2">
						<input
							name="artist_id"
							placeholder="Artist UUID"
							className="h-10 w-72 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none placeholder:text-gray-500 focus:border-white/20"
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
						<button className="inline-flex h-10 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-sm hover:bg-white/10">
							Add
						</button>
					</form>
				</div>
			</div>

			<FeaturedArtistsSuggest addFeaturedAction={addFeatured} defaultCountryCode="MW" />

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6 overflow-auto">
				<div className="flex items-center justify-between gap-4">
					<div>
						<h2 className="text-base font-semibold">Current Featured Artists</h2>
						<p className="mt-1 text-sm text-gray-400">{featuredRes.rows.length} entries</p>
					</div>
				</div>

				<div className="mt-4 min-w-[900px]">
					<div className="grid grid-cols-12 gap-3 border-b border-white/10 pb-2 text-xs text-gray-400">
						<div className="col-span-4">Artist</div>
						<div className="col-span-2">Country</div>
						<div className="col-span-2">Priority</div>
						<div className="col-span-2">Status</div>
						<div className="col-span-2 text-right">Actions</div>
					</div>

					{featuredRes.rows.map((r) => {
						const artist = artistsById.get(r.artist_id)
						const label =
							artist?.stage_name || artist?.display_name || artist?.name || r.artist_id
						return (
							<div key={r.id} className="grid grid-cols-12 gap-3 border-b border-white/5 py-3 text-sm">
								<div className="col-span-4">
									<div className="font-medium">{label}</div>
									<div className="mt-1 font-mono text-[11px] text-gray-500">{r.artist_id}</div>
								</div>
								<div className="col-span-2 text-gray-300">{r.country_code ?? '—'}</div>
								<div className="col-span-2">
									<form action={setPriority} className="flex items-center gap-2">
										<input type="hidden" name="id" value={r.id} />
										<input
											name="priority"
											defaultValue={r.priority ?? 0}
											className="h-9 w-20 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none focus:border-white/20"
										/>
										<button className="inline-flex h-9 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-xs hover:bg-white/10">
											Save
										</button>
									</form>
								</div>
								<div className="col-span-2">
									<span
										className={`inline-flex rounded-xl px-2 py-1 text-xs ${
											r.is_active ? 'bg-emerald-500/15 text-emerald-200' : 'bg-gray-500/15 text-gray-300'
										}`}
									>
										{r.is_active ? 'Active' : 'Inactive'}
									</span>
								</div>
								<div className="col-span-2 flex justify-end gap-2">
									<form action={setActive}>
										<input type="hidden" name="id" value={r.id} />
										<input type="hidden" name="next" value={r.is_active ? 'false' : 'true'} />
										<button className="inline-flex h-9 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-xs hover:bg-white/10">
											{r.is_active ? 'Disable' : 'Enable'}
										</button>
									</form>
									<form action={removeFeatured}>
										<input type="hidden" name="id" value={r.id} />
										<button className="inline-flex h-9 items-center rounded-xl border border-red-500/30 bg-red-500/10 px-3 text-xs text-red-200 hover:bg-red-500/15">
											Remove
										</button>
									</form>
								</div>
							</div>
						)
					})}
				</div>
			</div>
		</div>
	)
}
