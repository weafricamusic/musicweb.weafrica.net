import Link from 'next/link'
import { redirect } from 'next/navigation'

import { getAdminContext } from '@/lib/admin/session'
import { computeAutomatedRiskFlags, persistRiskFlags, type RiskFlag } from '@/lib/admin/risk-flags'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { logAdminAction } from '@/lib/admin/audit'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

function severityBadge(sev: string) {
	const v = String(sev)
	const cls =
		v === 'critical'
			? 'border-red-500/40 bg-red-500/15 text-red-200'
			: v === 'high'
				? 'border-orange-500/40 bg-orange-500/15 text-orange-200'
				: v === 'medium'
					? 'border-amber-500/40 bg-amber-500/15 text-amber-200'
					: 'border-white/10 bg-white/5 text-gray-200'
	return <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] ${cls}`}>{v}</span>
}

async function runScanAction() {
	'use server'

	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		throw new Error('Forbidden')
	}

	const country = await getAdminCountryCode()
	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) {
		throw new Error('SUPABASE_SERVICE_ROLE_KEY is required for risk flag scan (no anon fallback).')
	}
	const supabase = supabaseAdmin

	const { flags } = await computeAutomatedRiskFlags({ supabase, days: 7, countryCode: country })
	const { inserted, error } = await persistRiskFlags({ supabase, flags })

	await logAdminAction({
		ctx,
		action: 'risk_flags_scan',
		target_type: 'risk_flags',
		target_id: country,
		meta: { inserted, computed: flags.length, error: error ?? null },
	}).catch(() => {})

	redirect(`/admin/analytics/flags?saved=${encodeURIComponent(String(inserted))}`)
}

function sortBySeverity(flags: RiskFlag[]): RiskFlag[] {
	const rank: Record<string, number> = { critical: 0, high: 1, medium: 2, low: 3 }
	return [...flags].sort((a, b) => (rank[a.severity] ?? 9) - (rank[b.severity] ?? 9))
}

export default async function FlagsPage(props: { searchParams: Promise<{ days?: string; saved?: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) redirect('/auth/login')

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		return (
			<div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
				<h1 className="text-lg font-semibold">Access denied</h1>
				<p className="mt-2 text-sm text-gray-400">You need Operations/Super or Finance permissions to view risk flags.</p>
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
	const days = Math.max(1, Math.min(30, Number(sp.days ?? '7') || 7))
	const saved = sp.saved ? Number(sp.saved) : null

	const country = await getAdminCountryCode()
	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) return <ServiceRoleRequired title="Service role required for risk flags" />
	const supabase = supabaseAdmin
	const hasServiceRole = true
	let serviceRoleProbeError: string | null = null
	if (supabaseAdmin) {
		try {
			// Probe access without assuming a specific schema/column name.
			// Some environments may have a legacy `countries` shape (e.g. `code` instead of `country_code`).
			const { error } = await supabaseAdmin.from('countries').select('*', { head: true, count: 'exact' }).limit(1)
			if (error) serviceRoleProbeError = `${error.code ?? ''} ${error.message}`.trim()
		} catch {
			serviceRoleProbeError = 'Unexpected error probing Supabase admin access'
		}
	}

	const scan = await computeAutomatedRiskFlags({ supabase, days, countryCode: country })
	const flags = sortBySeverity(scan.flags)

	const by = flags.reduce(
		(acc, f) => {
			acc[f.severity] = (acc[f.severity] ?? 0) + 1
			return acc
		},
		{} as Record<string, number>,
	)

	return (
		<div className="space-y-6">
			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<div className="flex items-start justify-between gap-4">
					<div>
						<h1 className="text-2xl font-bold">Automated Flags & Suggestions</h1>
						<p className="mt-1 text-sm text-gray-400">Anomaly/risk signals across creators, streams, and payouts.</p>
						<p className="mt-2 text-xs text-gray-500">
							Range: last {days} days • Country: {country} • Service role: {hasServiceRole ? 'on' : 'off'}
						</p>
					</div>
					<div className="flex gap-2">
						<Link
							href="/admin/analytics"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Analytics
						</Link>
						<Link
							href="/admin/analytics/flags/saved"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Saved flags
						</Link>
						<Link
							href="/admin/analytics/timeline"
							className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5"
						>
							Timeline
						</Link>
						<form action={runScanAction}>
							<button className="inline-flex h-10 items-center rounded-xl bg-white/10 px-4 text-sm hover:bg-white/15" type="submit">
								Save flags
							</button>
						</form>
					</div>
				</div>

				{saved != null ? (
					<div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200">
						Saved {saved} new flag(s) to <code>risk_flags</code>.
					</div>
				) : null}
			</div>

			{scan.warnings.length ? (
				<div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
					<b>Partial scan:</b>
					{!hasServiceRole ? (
						<p className="mt-2 text-xs text-amber-200/90">
							Fix: set <code>SUPABASE_SERVICE_ROLE_KEY</code> in <code>.env.local</code> (make sure it is on a single line like
							 <code>SUPABASE_SERVICE_ROLE_KEY=...</code>), then restart <code>npm run dev</code>.
						</p>
					) : null}
					{hasServiceRole && serviceRoleProbeError ? (
						<p className="mt-2 text-xs text-amber-200/90">
							Admin access probe failed: <code>{serviceRoleProbeError}</code>
						</p>
					) : null}
					<ul className="mt-2 list-disc pl-6">
						{scan.warnings.map((w) => (
							<li key={w}>{w}</li>
						))}
					</ul>
				</div>
			) : null}

			<div className="grid grid-cols-2 gap-3 md:grid-cols-4">
				<div className="rounded-2xl border border-white/10 bg-white/5 p-4">
					<p className="text-xs text-gray-400">Critical</p>
					<p className="mt-1 text-xl font-semibold">{by.critical ?? 0}</p>
				</div>
				<div className="rounded-2xl border border-white/10 bg-white/5 p-4">
					<p className="text-xs text-gray-400">High</p>
					<p className="mt-1 text-xl font-semibold">{by.high ?? 0}</p>
				</div>
				<div className="rounded-2xl border border-white/10 bg-white/5 p-4">
					<p className="text-xs text-gray-400">Medium</p>
					<p className="mt-1 text-xl font-semibold">{by.medium ?? 0}</p>
				</div>
				<div className="rounded-2xl border border-white/10 bg-white/5 p-4">
					<p className="text-xs text-gray-400">Low</p>
					<p className="mt-1 text-xl font-semibold">{by.low ?? 0}</p>
				</div>
			</div>

			<div className="rounded-2xl border border-white/10 bg-white/5 p-6">
				<h2 className="text-base font-semibold">Flags</h2>
				<p className="mt-1 text-sm text-gray-400">
					These are computed live from <code>transactions</code>, <code>withdrawals</code>, and <code>live_streams</code> (plus metadata conventions).
				</p>

				{flags.length ? (
					<div className="mt-4 space-y-3">
						{flags.slice(0, 100).map((f) => (
							<div key={f.fingerprint} className="rounded-xl border border-white/10 bg-black/20 p-4">
								<div className="flex items-start justify-between gap-3">
									<div>
										<div className="flex items-center gap-2">
											{severityBadge(f.severity)}
											<p className="text-sm font-semibold">{f.title}</p>
										</div>
										<p className="mt-1 text-sm text-gray-300">{f.description}</p>
										<p className="mt-2 text-xs text-gray-500">
											{f.kind} • {f.entity_type}:{f.entity_id}
										</p>
									</div>
									<div className="flex flex-wrap gap-2">
										{(f.suggested_actions ?? []).map((a, idx) =>
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
									<summary className="cursor-pointer text-xs text-gray-400 hover:text-gray-200">Evidence</summary>
									<pre className="mt-2 overflow-auto rounded-lg border border-white/10 bg-black/30 p-3 text-[11px] text-gray-200">{JSON.stringify(f.evidence ?? {}, null, 2)}</pre>
								</details>
							</div>
						))}
					</div>
				) : (
					<p className="mt-4 text-sm text-gray-400">No flags detected for this window.</p>
				)}
			</div>
		</div>
	)
}
