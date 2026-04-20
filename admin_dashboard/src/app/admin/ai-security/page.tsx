import Link from 'next/link'
import { redirect } from 'next/navigation'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

type AiAlert = {
	id: string
	type: string
	reference_id: string
	severity: string
	message: string
	created_at: string
	resolved: boolean
	resolved_at?: string | null
	resolved_by_email?: string | null
}

function severityBadge(sev: string) {
	const v = String(sev)
	const cls =
		v === 'high'
			? 'border-orange-500/40 bg-orange-500/15 text-orange-200'
			: v === 'medium'
				? 'border-amber-500/40 bg-amber-500/15 text-amber-200'
				: 'border-white/10 bg-white/5 text-gray-200'
	return <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] ${cls}`}>{v}</span>
}

function typeBadge(t: string) {
	const v = String(t)
	return <span className="inline-flex items-center rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[11px] text-gray-200">{v}</span>
}

async function resolveAlertAction(formData: FormData) {
	'use server'

	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		throw new Error('Forbidden')
	}

	const id = String(formData.get('id') ?? '').trim()
	if (!id) throw new Error('Missing id')

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) throw new Error('SUPABASE_SERVICE_ROLE_KEY is required')

	const { error } = await supabase
		.from('ai_alerts')
		.update({ resolved: true, resolved_at: new Date().toISOString(), resolved_by_email: ctx.admin.email })
		.eq('id', id)

	await logAdminAction({
		ctx,
		action: 'ai_alert_resolve',
		target_type: 'ai_alerts',
		target_id: id,
		meta: { ok: !error, error: error?.message ?? null },
	}).catch(() => {})

	if (error) throw new Error(error.message)

	redirect('/admin/ai-security')
}

export default async function AiSecurityPage() {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You need Operations/Super or Finance permissions to view AI Security alerts.</p>
				<div className="mt-4">
					<Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
						Return to overview
					</Link>
				</div>
			</div>
		)
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return <ServiceRoleRequired title="Service role required for AI Security" />

	const { data, error } = await supabase
		.from('ai_alerts')
		.select('id,type,reference_id,severity,message,created_at,resolved,resolved_at,resolved_by_email')
		.order('created_at', { ascending: false })
		.limit(200)

	const alerts = (data ?? []) as AiAlert[]

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-2xl font-bold">AI Security</h1>
						<p className="mt-1 text-sm text-gray-400">Rule-based fraud detectors (no OpenAI). Review alerts and resolve.</p>
						<p className="mt-2 text-xs text-gray-500">Showing latest {Math.min(200, alerts.length)} alerts</p>
					</div>
					<div className="flex gap-2">
						<Link href="/admin/system-risk" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
							System &amp; Risk
						</Link>
					</div>
				</div>
				{error ? (
					<div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error.message}</div>
				) : null}
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="overflow-auto">
					<table className="min-w-full text-left text-sm">
						<thead className="text-xs uppercase tracking-wider text-zinc-500">
							<tr>
								<th className="py-3 pr-4">Type</th>
								<th className="py-3 pr-4">Severity</th>
								<th className="py-3 pr-4">Message</th>
								<th className="py-3 pr-4">Time</th>
								<th className="py-3">Action</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-white/5">
							{alerts.length ? (
								alerts.map((a) => (
									<tr key={a.id} className={a.resolved ? 'opacity-60' : ''}>
										<td className="py-3 pr-4 align-top">{typeBadge(a.type)}</td>
										<td className="py-3 pr-4 align-top">{severityBadge(a.severity)}</td>
										<td className="py-3 pr-4 align-top">
											<div className="text-gray-200">{a.message}</div>
											<div className="mt-1 text-[11px] text-gray-500">ref: {a.reference_id}</div>
										</td>
										<td className="py-3 pr-4 align-top text-xs text-gray-400">{new Date(a.created_at).toLocaleString()}</td>
										<td className="py-3 align-top">
											{a.resolved ? (
												<span className="text-xs text-gray-400">Resolved</span>
											) : (
												<form action={resolveAlertAction}>
													<input type="hidden" name="id" value={a.id} />
													<button type="submit" className="inline-flex h-9 items-center rounded-xl bg-white/10 px-3 text-xs hover:bg-white/15">
														Resolve
													</button>
												</form>
											)}
										</td>
									</tr>
								))
							) : (
								<tr>
									<td className="py-6 text-sm text-gray-400" colSpan={5}>
										No alerts yet.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</div>
		</div>
	)
}
