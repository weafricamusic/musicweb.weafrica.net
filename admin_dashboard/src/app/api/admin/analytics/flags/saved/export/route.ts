import { NextResponse } from 'next/server'

import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { toCsv } from '@/lib/admin/csv'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function normalizeText(raw: string | null, max: number): string | null {
	const v = (raw ?? '').trim()
	if (!v) return null
	return v.length > max ? v.slice(0, max) : v
}

function clampInt(raw: string | null, min: number, max: number, fallback: number): number {
	const n = Number(raw ?? '')
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.floor(n)))
}

export async function GET(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	if (!(ctx.permissions.can_manage_finance || ctx.admin.role === 'super_admin' || ctx.admin.role === 'operations_admin')) {
		return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return NextResponse.json({ error: 'Service role is required (SUPABASE_SERVICE_ROLE_KEY)' }, { status: 500 })

	const url = new URL(req.url)
	const status = (url.searchParams.get('status') ?? 'open').toLowerCase()
	const severity = (url.searchParams.get('severity') ?? '').toLowerCase()
	const kind = normalizeText(url.searchParams.get('kind'), 80)
	const q = normalizeText(url.searchParams.get('q'), 120)
	const limit = clampInt(url.searchParams.get('limit'), 25, 5000, 500)

	let query = supabase
		.from('risk_flags')
		.select(
			'id,created_at,status,severity,kind,entity_type,entity_id,country_code,title,description,evidence,suggested_actions,fingerprint,resolved_at,resolved_by_email,resolution_note',
		)
		.order('created_at', { ascending: false })
		.limit(limit)

	if (['open', 'dismissed', 'resolved'].includes(status)) query = query.eq('status', status)
	if (['low', 'medium', 'high', 'critical'].includes(severity)) query = query.eq('severity', severity)
	if (kind) query = query.eq('kind', kind)
	if (q) query = query.or(`title.ilike.%${q}%,description.ilike.%${q}%,entity_id.ilike.%${q}%`)

	const { data, error } = await query
	if (error) return NextResponse.json({ error: error.message }, { status: 500 })

	const rows = ((data ?? []) as any[]).map((r) => ({
		id: r.id ?? null,
		created_at: r.created_at ?? null,
		status: r.status ?? null,
		severity: r.severity ?? null,
		kind: r.kind ?? null,
		entity_type: r.entity_type ?? null,
		entity_id: r.entity_id ?? null,
		country_code: r.country_code ?? null,
		title: r.title ?? null,
		description: r.description ?? null,
		evidence: r.evidence ? JSON.stringify(r.evidence) : null,
		suggested_actions: r.suggested_actions ? JSON.stringify(r.suggested_actions) : null,
		fingerprint: r.fingerprint ?? null,
		resolved_at: r.resolved_at ?? null,
		resolved_by_email: r.resolved_by_email ?? null,
		resolution_note: r.resolution_note ?? null,
	}))

	const csv = toCsv(
		[
			'id',
			'created_at',
			'status',
			'severity',
			'kind',
			'entity_type',
			'entity_id',
			'country_code',
			'title',
			'description',
			'evidence',
			'suggested_actions',
			'fingerprint',
			'resolved_at',
			'resolved_by_email',
			'resolution_note',
		],
		rows,
	)

	const filename = `risk_flags_${status}_${new Date().toISOString().slice(0, 10)}.csv`

	await logAdminAction({
		ctx,
		action: 'risk_flags_export_csv',
		target_type: 'risk_flags',
		target_id: status,
		meta: { status, severity: severity || null, kind: kind || null, q: q || null, limit, rows: rows.length },
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
