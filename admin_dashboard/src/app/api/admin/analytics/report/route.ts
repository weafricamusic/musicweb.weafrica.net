import { NextResponse } from 'next/server'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { loadPlatformIntelligence } from '@/lib/admin/platform-intelligence'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function clampInt(raw: string | null, min: number, max: number, fallback: number): number {
	const n = Number(raw ?? '')
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.floor(n)))
}

function fmt(n: number | null | undefined): string {
	if (n == null) return '—'
	return new Intl.NumberFormat('en-US').format(n)
}

function fmtPct(n: number | null | undefined): string {
	if (n == null) return '—'
	const v = Math.round(Math.max(0, Math.min(1, n)) * 100)
	return `${v}%`
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	const url = new URL(req.url)
	const days = clampInt(url.searchParams.get('days'), 1, 90, 7)
	const qCountry = (url.searchParams.get('country') ?? '').trim().toUpperCase()
	const cookieCountry = await getAdminCountryCode().catch(() => null)
	const country = qCountry || (cookieCountry ? String(cookieCountry).toUpperCase() : '')

	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin analytics report (no anon fallback).' },
			{ status: 500 },
		)
	}
	const supabase = supabaseAdmin
	const intel = await loadPlatformIntelligence({ supabase, days, countryCode: country || null })

	let openFlags: any[] = []
	let flagsWarning: string | null = null
	try {
		const { data, error } = await supabaseAdmin
			.from('risk_flags')
			.select('created_at,severity,kind,entity_type,entity_id,title')
			.eq('status', 'open')
			.order('created_at', { ascending: false })
			.limit(50)
		if (error) throw error
		openFlags = (data ?? []) as any[]
	} catch (e) {
		flagsWarning = e instanceof Error ? e.message : 'Failed to load risk_flags'
		openFlags = []
	}

	const generatedAt = new Date().toLocaleString()
	const title = `WeAfrica Admin Report (${intel.range.days}d${country ? ` • ${country}` : ''})`

	const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title}</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial; margin: 24px; color: #0b1020; }
    h1 { font-size: 20px; margin: 0 0 6px 0; }
    .meta { color: #475569; font-size: 12px; margin-bottom: 18px; }
    .grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
    .card { border: 1px solid #e2e8f0; border-radius: 14px; padding: 12px; }
    .label { font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: 0.03em; }
    .value { font-size: 18px; font-weight: 700; margin-top: 6px; }
    h2 { font-size: 14px; margin: 20px 0 10px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border-bottom: 1px solid #e2e8f0; padding: 8px; text-align: left; font-size: 12px; }
    th { color: #475569; font-weight: 700; }
    .muted { color: #64748b; font-size: 12px; }
    @media print {
      body { margin: 0; }
    }
  </style>
</head>
<body>
  <h1>${title}</h1>
  <div class="meta">Generated: ${generatedAt} • Admin: ${ctx.admin.email ?? '—'}</div>

  <h2>Summary</h2>
  <div class="grid">
    <div class="card"><div class="label">Revenue (MWK)</div><div class="value">${fmt(intel.revenueMwk7d as any)}</div></div>
    <div class="card"><div class="label">Coins Sold</div><div class="value">${fmt(intel.coinsSold7d as any)}</div></div>
    <div class="card"><div class="label">New Users</div><div class="value">${fmt(intel.newUsers7d as any)}</div></div>
    <div class="card"><div class="label">Pending Withdrawals</div><div class="value">${fmt(intel.pendingWithdrawalsCount as any)}</div></div>

    <div class="card"><div class="label">Open Reports</div><div class="value">${fmt(intel.openReports as any)}</div></div>
    <div class="card"><div class="label">Frozen Accounts</div><div class="value">${fmt(intel.frozenEarningsAccounts as any)}</div></div>
    <div class="card"><div class="label">DAU (1d)</div><div class="value">${fmt(intel.dau1d as any)}</div></div>
    <div class="card"><div class="label">Join Success</div><div class="value">${fmtPct(intel.streamJoinSuccessRate as any)}</div></div>
  </div>

  <h2>Open Risk Flags</h2>
  ${flagsWarning ? `<div class="muted">${flagsWarning}</div>` : ''}
  <table>
    <thead>
      <tr><th>When</th><th>Severity</th><th>Kind</th><th>Entity</th><th>Title</th></tr>
    </thead>
    <tbody>
      ${openFlags
			.slice(0, 30)
			.map((f) => {
				const when = f.created_at ? new Date(String(f.created_at)).toLocaleString() : '—'
				const entity = [f.entity_type, f.entity_id].filter(Boolean).join(':') || '—'
				return `<tr><td>${when}</td><td>${String(f.severity ?? '—')}</td><td>${String(f.kind ?? '—')}</td><td>${entity}</td><td>${String(
					f.title ?? '—',
				)}</td></tr>`
			})
			.join('')}
      ${openFlags.length ? '' : '<tr><td colspan="5" class="muted">No open flags found.</td></tr>'}
    </tbody>
  </table>
</body>
</html>`

	await logAdminAction({
		ctx,
		action: 'analytics_report_html',
		target_type: 'analytics_report',
		target_id: country || 'ALL',
		meta: { days: intel.range.days, open_flags: openFlags.length },
		req,
	}).catch(() => {})

	const filename = `report_${country || 'ALL'}_${intel.range.days}d_${new Date().toISOString().slice(0, 10)}.html`
	return new NextResponse(html, {
		status: 200,
		headers: {
			'content-type': 'text/html; charset=utf-8',
			'content-disposition': `attachment; filename="${filename}"`,
			'cache-control': 'no-store',
		},
	})
}
