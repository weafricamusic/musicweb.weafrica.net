import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

type TaxonomyRow = {
	id: string
	name: string
	is_active: boolean
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

function normalizeName(raw: FormDataEntryValue | null, maxLen = 64): string {
	const v = typeof raw === 'string' ? raw.trim() : ''
	return v.slice(0, maxLen)
}

async function loadRows(table: 'genres' | 'categories'): Promise<{ rows: TaxonomyRow[]; missing: boolean }>{
	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return { rows: [], missing: false }

	try {
		const { data, error } = await supabase
			.from(table)
			.select('id,name,is_active,created_at,updated_at')
			.order('is_active', { ascending: false })
			.order('name', { ascending: true })
			.limit(500)
		if (error) {
			if (isMissingTableError(error)) return { rows: [], missing: true }
			return { rows: [], missing: false }
		}
		return { rows: (data ?? []) as unknown as TaxonomyRow[], missing: false }
	} catch (e) {
		if (isMissingTableError(e)) return { rows: [], missing: true }
		return { rows: [], missing: false }
	}
}

export default async function GenresCategoriesPage(props: { searchParams?: Promise<{ ok?: string; error?: string }> }) {
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
				<p className="mt-2 text-sm text-gray-400">You don’t have permission to manage content taxonomy.</p>
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
					<h1 className="text-lg font-semibold">Genres & Categories</h1>
					<p className="mt-1 text-sm text-gray-400">Manage the allowed taxonomy used when tagging content.</p>
				</div>
				<ServiceRoleRequired title="Service role required for taxonomy management" />
			</div>
		)
	}

	const [genresRes, categoriesRes] = await Promise.all([loadRows('genres'), loadRows('categories')])

	async function createItem(formData: FormData) {
		'use server'
		const ctx = await getAdminContext()
		if (!ctx) redirect('/auth/login')

		const canManage =
			ctx.admin.role === 'super_admin' ||
			ctx.admin.role === 'operations_admin' ||
			ctx.permissions.can_manage_artists
		if (!canManage) redirect('/admin/genres-categories?error=forbidden')

		const table = asString(formData.get('table')).trim() as 'genres' | 'categories'
		if (!(table === 'genres' || table === 'categories')) redirect('/admin/genres-categories?error=invalid_table')

		const name = normalizeName(formData.get('name'))
		if (!name) redirect('/admin/genres-categories?error=missing_name')

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/genres-categories?error=service_role_required')

		try {
			const { data: existing } = await supabaseAdmin
				.from(table)
				.select('id,name,is_active')
				.ilike('name', name)
				.limit(1)
				.maybeSingle()

			if (existing?.id) {
				// If it exists but was deactivated, reactivate.
				if (existing.is_active === false) {
					const { error } = await supabaseAdmin.from(table).update({ is_active: true }).eq('id', existing.id)
					if (error) throw error

					await logAdminAction({
						ctx,
						action: `${table}.reactivate`,
						target_type: table,
						target_id: existing.id,
						before_state: { is_active: false },
						after_state: { is_active: true },
						meta: { name: existing.name },
					})
				}
				redirect('/admin/genres-categories?ok=1')
			}

			const { data, error } = await supabaseAdmin
				.from(table)
				.insert({ name, is_active: true })
				.select('id,name,is_active')
				.limit(1)
				.single()
			if (error) throw error

			await logAdminAction({
				ctx,
				action: `${table}.create`,
				target_type: table,
				target_id: data.id,
				before_state: null,
				after_state: { name: data.name, is_active: data.is_active },
				meta: { module: 'taxonomy' },
			})

			redirect('/admin/genres-categories?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'create_failed'
			redirect(`/admin/genres-categories?error=${encodeURIComponent(msg)}`)
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
		if (!canManage) redirect('/admin/genres-categories?error=forbidden')

		const table = asString(formData.get('table')).trim() as 'genres' | 'categories'
		if (!(table === 'genres' || table === 'categories')) redirect('/admin/genres-categories?error=invalid_table')

		const id = asString(formData.get('id')).trim()
		if (!id) redirect('/admin/genres-categories?error=missing_id')

		const next = asString(formData.get('next')).trim()
		if (!(next === 'true' || next === 'false')) redirect('/admin/genres-categories?error=invalid_value')
		const nextVal = next === 'true'

		const supabaseAdmin = tryCreateSupabaseAdminClient()
		if (!supabaseAdmin) redirect('/admin/genres-categories?error=service_role_required')

		let before: Record<string, unknown> | null = null
		try {
			const { data } = await supabaseAdmin
				.from(table)
				.select('name,is_active')
				.eq('id', id)
				.limit(1)
				.maybeSingle()
			before = (data ?? null) as unknown as Record<string, unknown> | null
		} catch {
			before = null
		}

		try {
			const { error } = await supabaseAdmin.from(table).update({ is_active: nextVal }).eq('id', id)
			if (error) throw error

			await logAdminAction({
				ctx,
				action: `${table}.set_active`,
				target_type: table,
				target_id: id,
				before_state: before,
				after_state: { is_active: nextVal },
				meta: { module: 'taxonomy' },
			})

			redirect('/admin/genres-categories?ok=1')
		} catch (e) {
			const msg = e instanceof Error ? e.message : 'update_failed'
			redirect(`/admin/genres-categories?error=${encodeURIComponent(msg)}`)
		}
	}

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-lg font-semibold">Genres & Categories</h1>
						<p className="mt-1 text-sm text-gray-400">Manage the allowed taxonomy used when tagging content.</p>
						<p className="mt-3 text-xs text-gray-500">
							Tip: The admin track upload still allows free-text genre input; this page is for standardizing the list.
						</p>
					</div>
					<div className="flex gap-2">
						<Link href="/admin/tracks/upload" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Upload track</Link>
						<a href="/api/admin/taxonomy" target="_blank" rel="noreferrer" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">API preview</a>
					</div>
				</div>
			</div>

			{sp.ok ? (
				<div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm text-emerald-200">Saved.</div>
			) : null}
			{sp.error ? (
				<div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">{sp.error}</div>
			) : null}

			{genresRes.missing || categoriesRes.missing ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
					<p className="font-semibold">Database tables not found</p>
					<p className="mt-1 text-xs text-amber-100/90">
						Create them by running the new migration: <span className="font-mono">20260202100000_genres_categories.sql</span>
					</p>
				</div>
			) : null}

			<div className="grid gap-4 lg:grid-cols-2">
				<TaxonomyPanel title="Genres" table="genres" rows={genresRes.rows} onCreate={createItem} onSetActive={setActive} />
				<TaxonomyPanel title="Categories" table="categories" rows={categoriesRes.rows} onCreate={createItem} onSetActive={setActive} />
			</div>
		</div>
	)
}

function TaxonomyPanel(props: {
	title: string
	table: 'genres' | 'categories'
	rows: TaxonomyRow[]
	onCreate: (formData: FormData) => Promise<void>
	onSetActive: (formData: FormData) => Promise<void>
}) {
	return (
		<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
			<div className="flex items-start justify-between gap-4">
				<div>
					<h2 className="text-base font-semibold">{props.title}</h2>
					<p className="mt-1 text-xs text-gray-400">{props.rows.length} items</p>
				</div>
				<form action={props.onCreate} className="flex items-center gap-2">
					<input type="hidden" name="table" value={props.table} />
					<input
						name="name"
						placeholder={`Add ${props.title.toLowerCase()}…`}
						className="h-10 w-44 rounded-xl border border-white/10 bg-black/20 px-3 text-sm outline-none placeholder:text-gray-500 focus:border-white/20"
					/>
					<button className="inline-flex h-10 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-sm hover:bg-white/10">Add</button>
				</form>
			</div>

			<div className="mt-4 overflow-auto">
				<table className="w-full min-w-[520px] border-separate border-spacing-0 text-left text-sm">
					<thead>
						<tr className="text-gray-400">
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Name</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
							<th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
						</tr>
					</thead>
					<tbody>
						{props.rows.map((r) => (
							<tr key={r.id} className="text-gray-200">
								<td className="border-b border-white/5 py-3 pr-4">
									<span className={r.is_active ? '' : 'text-gray-500 line-through'}>{r.name}</span>
								</td>
								<td className="border-b border-white/5 py-3 pr-4">
									{r.is_active ? (
										<span className="rounded-full bg-emerald-500/15 px-2 py-1 text-xs text-emerald-200">Active</span>
									) : (
										<span className="rounded-full bg-gray-500/15 px-2 py-1 text-xs text-gray-300">Inactive</span>
									)}
								</td>
								<td className="border-b border-white/5 py-3 pr-4">
									<form action={props.onSetActive} className="inline-flex">
										<input type="hidden" name="table" value={props.table} />
										<input type="hidden" name="id" value={r.id} />
										<input type="hidden" name="next" value={r.is_active ? 'false' : 'true'} />
										<button className="inline-flex h-9 items-center rounded-xl border border-white/10 bg-white/5 px-3 text-xs hover:bg-white/10">
											{r.is_active ? 'Deactivate' : 'Activate'}
										</button>
									</form>
								</td>
							</tr>
						))}
						{props.rows.length === 0 ? (
							<tr>
								<td colSpan={3} className="py-6 text-center text-sm text-gray-500">
									No items yet.
								</td>
							</tr>
						) : null}
					</tbody>
				</table>
			</div>
		</div>
	)
}
