import Link from 'next/link'
import { redirect } from 'next/navigation'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

type RiskFlagRow = {
	id: number
	created_at: string
	status: 'open' | 'dismissed' | 'resolved'
	severity: 'low' | 'medium' | 'high' | 'critical'
	kind: string
	entity_type: 'artist' | 'dj' | 'stream' | 'withdrawal'
	entity_id: string
	country_code: string | null
	title: string
	description: string
	evidence: Record<string, unknown>
	suggested_actions: Array<{ label: string; href?: string; kind?: string }>
	fingerprint: string
	resolved_at: string | null
	resolved_by_email: string | null
	resolution_note: string | null
}

function badge(label: string, variant: 'gray' | 'amber' | 'red' | 'orange' | 'green' = 'gray') {
	const cls =
		variant === 'red'
			? 'border-red-500/40 bg-red-500/15 text-red-200'
			: variant === 'orange'
				? 'border-orange-500/40 bg-orange-500/15 text-orange-200'
				: variant === 'amber'
					? 'border-amber-500/40 bg-amber-500/15 text-amber-200'
					: variant === 'green'
						? 'border-emerald-500/40 bg-emerald-500/15 text-emerald-200'
						: 'border-white/10 bg-white/5 text-gray-200'
	return <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] ${cls}`}>{label}</span>
}

function severityVariant(sev: string): 'gray' | 'amber' | 'orange' | 'red' {
	const v = String(sev)
	if (v === 'critical') return 'red'
	if (v === 'high') return 'orange'
	if (v === 'medium') return 'amber'
	return 'gray'
}

function statusVariant(status: string): 'gray' | 'green' {
	return status === 'open' ? 'gray' : 'green'
}

async function updateFlagStatusAction(formData: FormData) {
	'use server'

	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		throw new Error('Forbidden')
	}

	const id = Number(formData.get('id'))
	const status = String(formData.get('status') ?? '')
	const note = String(formData.get('note') ?? '').trim()
	const returnTo = String(formData.get('returnTo') ?? '/admin/analytics/flags/saved')

	if (!Number.isFinite(id) || id <= 0) throw new Error('Invalid id')
	if (!['open', 'dismissed', 'resolved'].includes(status)) throw new Error('Invalid status')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY (required for risk_flags)')

	const { data: beforeRow } = await supabase.from('risk_flags').select('*').eq('id', id).maybeSingle()

	const nowIso = new Date().toISOString()
	const patch: Record<string, unknown> = { status }
	if (status === 'open') {
		patch.resolved_at = null
		patch.resolved_by_email = null
		patch.resolution_note = null
	} else {
		patch.resolved_at = nowIso
		patch.resolved_by_email = ctx.admin.email
		patch.resolution_note = note || null
	}

	const { data: afterRow, error } = await supabase.from('risk_flags').update(patch).eq('id', id).select('*').maybeSingle()
	if (error) throw new Error(error.message)

	await logAdminAction({
		ctx,
		action: status === 'open' ? 'risk_flag_reopened' : status === 'resolved' ? 'risk_flag_resolved' : 'risk_flag_dismissed',
		target_type: 'risk_flags',
		target_id: String(id),
		before_state: (beforeRow as any) ?? null,
		after_state: (afterRow as any) ?? null,
		meta: { note: note || null },
	}).catch(() => {})

	redirect(returnTo)
}

export default async function SavedFlagsPage(props: {
	searchParams: Promise<{ status?: string; severity?: string; kind?: string; q?: string; limit?: string }>
}) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You need Operations/Super or Finance permissions to manage saved risk flags.</p>
				<div className="mt-4">
					<Link
						href="/admin/analytics"
						className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
					>
						Back to analytics
					</Link>
				</div>
			</div>
		)
	}

	const sp = await props.searchParams
	const status = (sp.status ?? 'open').toLowerCase()
	const severity = (sp.severity ?? '').toLowerCase()
	const kind = (sp.kind ?? '').trim()
	const q = (sp.q ?? '').trim()
	const limit = Math.max(25, Math.min(300, Number(sp.limit ?? '100') || 100))

	const supabase = tryCreateSupabaseAdminClient()
	const hasServiceRole = !!supabase

	let rows: RiskFlagRow[] = []
	let counts: Record<string, number> = {}
	let loadWarning: string | null = null

	if (!supabase) {
		loadWarning = 'Set SUPABASE_SERVICE_ROLE_KEY to view saved risk flags.'
	} else {
		let query = supabase.from('risk_flags').select('*').order('created_at', { ascending: false }).limit(limit)
		if (status && status !== 'all') query = query.eq('status', status)
		if (severity) query = query.eq('severity', severity)
		if (kind) query = query.eq('kind', kind)
		if (q) query = query.or(`title.ilike.%${q}%,description.ilike.%${q}%,entity_id.ilike.%${q}%`)

		const [{ data, error }, { data: openRows }, { data: resolvedRows }, { data: dismissedRows }] = await Promise.all([
			query,
			supabase.from('risk_flags').select('id').eq('status', 'open').limit(5000),
			supabase.from('risk_flags').select('id').eq('status', 'resolved').limit(5000),
			supabase.from('risk_flags').select('id').eq('status', 'dismissed').limit(5000),
		])

		if (error) {
			loadWarning = error.message
		} else {
			rows = (data ?? []) as any
		}

		counts = {
			open: Array.isArray(openRows) ? openRows.length : 0,
			resolved: Array.isArray(resolvedRows) ? resolvedRows.length : 0,
			dismissed: Array.isArray(dismissedRows) ? dismissedRows.length : 0,
		}
	}

	const baseHref = '/admin/analytics/flags/saved'
	const currentUrl = `${baseHref}?status=${encodeURIComponent(status || 'open')}${severity ? `&severity=${encodeURIComponent(severity)}` : ''}${kind ? `&kind=${encodeURIComponent(kind)}` : ''}${q ? `&q=${encodeURIComponent(q)}` : ''}&limit=${encodeURIComponent(String(limit))}`
	const exportHref =
		`/api/admin/analytics/flags/saved/export?status=${encodeURIComponent(status || 'open')}` +
		(severity ? `&severity=${encodeURIComponent(severity)}` : '') +
		(kind ? `&kind=${encodeURIComponent(kind)}` : '') +
		(q ? `&q=${encodeURIComponent(q)}` : '') +
		`&limit=${encodeURIComponent(String(limit))}`

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-2xl font-bold">Saved Risk Flags</h1>
						<p className="mt-1 text-sm text-gray-400">Persisted anomaly signals from scans (status workflow: open → resolved/dismissed).</p>
						{hasServiceRole ? (
							<p className="mt-2 text-xs text-gray-500">
								Open: {counts.open ?? 0} • Resolved: {counts.resolved ?? 0} • Dismissed: {counts.dismissed ?? 0}
							</p>
						) : null}
					</div>
					<div className="flex gap-2">
						<Link
							href="/admin/analytics"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Analytics
						</Link>
						<Link
							href={exportHref}
							prefetch={false}
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Export CSV
						</Link>
						<Link
							href="/admin/analytics/flags"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Run scan
						</Link>
					</div>
				</div>
			</div>

			{loadWarning ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
					<b>Saved flags unavailable:</b> {loadWarning}
				</div>
			) : null}

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Filters</h2>
				<div className="mt-3 flex flex-wrap items-center gap-2">
					<Link
						href={`${baseHref}?status=open&limit=${encodeURIComponent(String(limit))}`}
						className={`inline-flex h-9 items-center rounded-xl border px-3 text-sm hover:bg-white/5 ${status === 'open' ? 'border-white/20 bg-white/10' : 'border-white/10'}`}
					>
						Open
					</Link>
					<Link
						href={`${baseHref}?status=resolved&limit=${encodeURIComponent(String(limit))}`}
						className={`inline-flex h-9 items-center rounded-xl border px-3 text-sm hover:bg-white/5 ${status === 'resolved' ? 'border-white/20 bg-white/10' : 'border-white/10'}`}
					>
						Resolved
					</Link>
					<Link
						href={`${baseHref}?status=dismissed&limit=${encodeURIComponent(String(limit))}`}
						className={`inline-flex h-9 items-center rounded-xl border px-3 text-sm hover:bg-white/5 ${status === 'dismissed' ? 'border-white/20 bg-white/10' : 'border-white/10'}`}
					>
						Dismissed
					</Link>
					<Link
						href={`${baseHref}?status=all&limit=${encodeURIComponent(String(limit))}`}
						className={`inline-flex h-9 items-center rounded-xl border px-3 text-sm hover:bg-white/5 ${status === 'all' ? 'border-white/20 bg-white/10' : 'border-white/10'}`}
					>
						All
					</Link>
				</div>

				<form className="mt-4 grid gap-3 md:grid-cols-4" action="/admin/analytics/flags/saved" method="get">
					<input type="hidden" name="status" value={status || 'open'} />
					<div>
						<label className="text-xs text-gray-400">Severity</label>
						<select
							name="severity"
							defaultValue={severity}
							className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						>
							<option value="">Any</option>
							<option value="critical">critical</option>
							<option value="high">high</option>
							<option value="medium">medium</option>
							<option value="low">low</option>
						</select>
					</div>
					<div>
						<label className="text-xs text-gray-400">Kind</label>
						<input
							name="kind"
							defaultValue={kind}
							placeholder="e.g. payout_above_threshold"
							className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</div>
					<div>
						<label className="text-xs text-gray-400">Search</label>
						<input
							name="q"
							defaultValue={q}
							placeholder="title, description, entity id"
							className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						/>
					</div>
					<div>
						<label className="text-xs text-gray-400">Limit</label>
						<select
							name="limit"
							defaultValue={String(limit)}
							className="mt-1 h-10 w-full rounded-xl border border-white/10 bg-black/30 px-3 text-sm"
						>
							<option value="50">50</option>
							<option value="100">100</option>
							<option value="200">200</option>
							<option value="300">300</option>
						</select>
					</div>
					<div className="md:col-span-4 flex gap-2">
						<button type="submit" className="inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15">
							Apply
						</button>
						<Link
							href={baseHref}
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Reset
						</Link>
					</div>
				</form>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Flags</h2>
				{rows.length ? (
					<div className="mt-4 space-y-3">
						{rows.map((f) => (
							<div key={String(f.id)} className="rounded-xl border border-white/10 bg-black/20 p-4">
								<div className="flex items-start justify-between gap-3">
									<div>
										<div className="flex flex-wrap items-center gap-2">
											{badge(f.severity, severityVariant(f.severity))}
											{badge(f.status, statusVariant(f.status))}
											<p className="text-sm font-semibold">{f.title}</p>
										</div>
										<p className="mt-1 text-sm text-gray-300">{f.description}</p>
										<p className="mt-2 text-xs text-gray-500">
											{new Date(f.created_at).toLocaleString()} • {f.kind} • {f.entity_type}:{f.entity_id}
											{f.country_code ? ` • ${f.country_code}` : ''}
										</p>
										{f.resolved_at ? (
											<p className="mt-1 text-xs text-gray-500">
												Closed: {new Date(f.resolved_at).toLocaleString()}
												{f.resolved_by_email ? ` • ${f.resolved_by_email}` : ''}
												{f.resolution_note ? ` • ${f.resolution_note}` : ''}
											</p>
										) : null}
									</div>
									<div className="flex flex-wrap justify-end gap-2">
										{(f.suggested_actions ?? []).slice(0, 3).map((a, idx) =>
											a.href ? (
												<Link
													key={idx}
													href={a.href}
													className="inline-flex h-8 items-center rounded-lg border border-white/10 px-3 text-xs hover:bg-white/5"
												>
													{a.label}
												</Link>
											) : null,
										)}
									</div>
								</div>

								<details className="mt-3">
									<summary className="cursor-pointer text-xs text-gray-400 hover:text-gray-200">Manage</summary>
									<div className="mt-3 grid gap-3 md:grid-cols-3">
										<form action={updateFlagStatusAction} className="rounded-xl border border-white/10 bg-black/30 p-3">
											<input type="hidden" name="id" value={String(f.id)} />
											<input type="hidden" name="status" value="resolved" />
											<input type="hidden" name="returnTo" value={currentUrl} />
											<p className="text-xs text-gray-400">Resolve</p>
											<input
												name="note"
												placeholder="Optional note"
												className="mt-2 h-9 w-full rounded-lg border border-white/10 bg-black/40 px-2 text-xs"
											/>
											<button
												type="submit"
												className="mt-2 inline-flex h-9 w-full items-center justify-center rounded-lg bg-white/10 text-xs hover:bg-white/15"
												disabled={!hasServiceRole}
											>
												Mark resolved
											</button>
										</form>

										<form action={updateFlagStatusAction} className="rounded-xl border border-white/10 bg-black/30 p-3">
											<input type="hidden" name="id" value={String(f.id)} />
											<input type="hidden" name="status" value="dismissed" />
											<input type="hidden" name="returnTo" value={currentUrl} />
											<p className="text-xs text-gray-400">Dismiss</p>
											<input
												name="note"
												placeholder="Optional note"
												className="mt-2 h-9 w-full rounded-lg border border-white/10 bg-black/40 px-2 text-xs"
											/>
											<button
												type="submit"
												className="mt-2 inline-flex h-9 w-full items-center justify-center rounded-lg bg-white/10 text-xs hover:bg-white/15"
												disabled={!hasServiceRole}
											>
												Dismiss
											</button>
										</form>

										<form action={updateFlagStatusAction} className="rounded-xl border border-white/10 bg-black/30 p-3">
											<input type="hidden" name="id" value={String(f.id)} />
											<input type="hidden" name="status" value="open" />
											<input type="hidden" name="returnTo" value={currentUrl} />
											<p className="text-xs text-gray-400">Reopen</p>
											<p className="mt-2 text-[11px] text-gray-500">Clears resolution fields.</p>
											<button
												type="submit"
												className="mt-3 inline-flex h-9 w-full items-center justify-center rounded-lg border border-white/10 text-xs hover:bg-white/5"
												disabled={!hasServiceRole}
											>
												Reopen
											</button>
										</form>
									</div>
								</details>

								<details className="mt-3">
									<summary className="cursor-pointer text-xs text-gray-400 hover:text-gray-200">Evidence</summary>
									<pre className="mt-2 overflow-auto rounded-lg border border-white/10 bg-black/30 p-3 text-[11px] text-gray-200">
										{JSON.stringify(f.evidence ?? {}, null, 2)}
									</pre>
								</details>
							</div>
						))}
					</div>
				) : (
					<p className="mt-4 text-sm text-gray-400">No saved flags match these filters.</p>
				)}
			</div>
		</div>
	)
}
