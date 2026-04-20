import { NextResponse } from 'next/server'

import { computeAutomatedRiskFlags, persistRiskFlags } from '@/lib/admin/risk-flags'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function getBearer(req: Request): string | null {
	const h = req.headers.get('authorization') ?? ''
	const m = /^bearer\s+(.+)$/i.exec(h.trim())
	return m?.[1]?.trim() || null
}

export async function POST(req: Request) {
	const secret = process.env.RISK_SCAN_SECRET
	if (!secret) {
		return NextResponse.json({ ok: false, error: 'RISK_SCAN_SECRET not set' }, { status: 500 })
	}

	const header = req.headers.get('x-risk-scan-secret')
	const token = header ?? getBearer(req)
	if (!token || token !== secret) {
		return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json({ ok: false, error: 'service role missing (SUPABASE_SERVICE_ROLE_KEY)' }, { status: 500 })
	}

	const url = new URL(req.url)
	const days = Math.max(1, Math.min(30, Number(url.searchParams.get('days') ?? '7') || 7))
	const countryCode = (url.searchParams.get('country') ?? '').trim().toUpperCase() || null

	const scan = await computeAutomatedRiskFlags({ supabase, days, countryCode })
	const saved = await persistRiskFlags({ supabase, flags: scan.flags })

	return NextResponse.json({
		ok: !saved.error,
		days,
		countryCode,
		computed: scan.flags.length,
		inserted: saved.inserted,
		warnings: scan.warnings,
		error: saved.error ?? null,
	})
}
