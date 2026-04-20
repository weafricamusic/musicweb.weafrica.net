import { NextResponse } from 'next/server'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'
import { toCsv } from '@/lib/admin/csv'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function normalizeLimit(raw: string | null): number {
	const n = Number(raw ?? '200')
	if (!Number.isFinite(n)) return 200
	return Math.max(50, Math.min(5000, Math.floor(n)))
}

function normalizeText(raw: string | null, max: number): string | null {
	const v = (raw ?? '').trim()
	if (!v) return null
	return v.length > max ? v.slice(0, max) : v
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	const url = new URL(req.url)
	const limit = normalizeLimit(url.searchParams.get('limit'))
	const kind = normalizeText(url.searchParams.get('kind'), 32) ?? 'analytics'
	const eventFilter = normalizeText(url.searchParams.get('event'), 80)

	const cookieCountry = await getAdminCountryCode().catch(() => null)
	const countryFilter =
		normalizeText(url.searchParams.get('country'), 8)?.toUpperCase() ?? (cookieCountry ? String(cookieCountry).toUpperCase() : null)

	const supabaseAdmin = tryCreateSupabaseAdminClient()
	if (!supabaseAdmin) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for timeline export (no anon fallback).' },
			{ status: 500 },
		)
	}
	const supabase = supabaseAdmin

	const rows: Array<Record<string, string | number | null>> = []
	let used: 'analytics_events' | 'admin_logs' = 'analytics_events'

	if (kind === 'admin') {
		used = 'admin_logs'
		let q = supabase
			.from('admin_logs')
			.select('created_at,action,admin_email,target_type,target_id,reason,meta')
			.order('created_at', { ascending: false })
			.limit(limit)
		if (eventFilter) q = q.ilike('action', `%${eventFilter}%`)
		const { data, error } = await q
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })
		for (const r of (data ?? []) as any[]) {
			rows.push({
				created_at: r.created_at ?? null,
				event: r.action ?? null,
				actor: r.admin_email ?? null,
				target: [r.target_type, r.target_id].filter(Boolean).join(':') || null,
				reason: r.reason ?? null,
				meta: r.meta ? JSON.stringify(r.meta) : null,
			})
		}
	} else {
		used = 'analytics_events'
		let q = supabaseAdmin
			.from('analytics_events')
			.select(
				'created_at,event_name,user_id,actor_type,actor_id,session_id,country_code,stream_id,platform,app_version,source,properties',
			)
			.order('created_at', { ascending: false })
			.limit(limit)
		if (countryFilter) q = q.eq('country_code', countryFilter)
		if (eventFilter) q = q.eq('event_name', eventFilter)
		const { data, error } = await q
		if (error) return NextResponse.json({ error: error.message }, { status: 500 })

		for (const r of (data ?? []) as any[]) {
			rows.push({
				created_at: r.created_at ?? null,
				event: r.event_name ?? null,
				actor: [r.user_id, r.actor_type, r.actor_id].filter(Boolean).join(' / ') || null,
				target: r.stream_id ?? null,
				country: r.country_code ?? null,
				platform: r.platform ?? null,
				app_version: r.app_version ?? null,
				source: r.source ?? null,
				properties: r.properties ? JSON.stringify(r.properties) : null,
			})
		}
	}

	const headers =
		used === 'admin_logs'
			? ['created_at', 'event', 'actor', 'target', 'reason', 'meta']
			: ['created_at', 'event', 'actor', 'target', 'country', 'platform', 'app_version', 'source', 'properties']

	const csv = toCsv(headers, rows)
	const filename = `timeline_${used}_${new Date().toISOString().slice(0, 10)}.csv`

	await logAdminAction({
		ctx,
		action: 'timeline_export_csv',
		target_type: used,
		target_id: countryFilter ?? 'ALL',
		meta: { kind, limit, event: eventFilter ?? null, rows: rows.length },
		req,
	}).catch(() => {})

	return new NextResponse(csv, {
		status: 200,
		headers: {
			'content-type': 'text/csv; charset=utf-8',
			'content-disposition': `attachment; filename="${filename}"`,
			'cache-control': 'no-store',
		},
	})
}
