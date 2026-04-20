import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function isMissingTable(err: unknown): boolean {
	if (!err || typeof err !== 'object') return false
	const rec = err as { message?: unknown; code?: unknown }
	const message = typeof rec.message === 'string' ? rec.message : ''
	const code = typeof rec.code === 'string' ? rec.code : ''
	return (
		code === '42P01' ||
		code === 'PGRST205' ||
		message.toLowerCase().includes('schema cache') ||
		message.toLowerCase().includes('could not find the table')
	)
}

const TABLE = 'announcements' as const

const TARGET_ORDER = ['artists', 'djs', 'consumers'] as const
const TARGET_SET = new Set<string>(TARGET_ORDER)

function targetIndex(value: string): number {
	const idx = TARGET_ORDER.findIndex((t) => t === value)
	return idx === -1 ? TARGET_ORDER.length : idx
}

function normalizeTarget(value: unknown): string {
	const raw = String(value ?? '').trim().toLowerCase()
	if (!raw) return ''
	if (raw === 'all') return 'all'

	const parts = raw
		.split(',')
		.map((s) => s.trim().toLowerCase())
		.filter(Boolean)

	const uniq: string[] = []
	for (const p of parts) {
		if (!TARGET_SET.has(p)) return ''
		if (!uniq.includes(p)) uniq.push(p)
	}

	uniq.sort((a, b) => targetIndex(a) - targetIndex(b))
	return uniq.join(',')
}

type CreateBody = {
	title: string
	message: string
	target: string
	action_link?: string | null
	is_active?: boolean
}

type AnnouncementRow = {
	id: string
	title: string
	message: string
	target: string
	action_link: string | null
	is_active: boolean
	created_at: string
}

export async function POST(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ ok: false, error: 'Unauthorized' }, { status: 401 })

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ ok: false, error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as CreateBody | null
	if (!body || typeof body !== 'object') return json({ ok: false, error: 'Invalid body' }, { status: 400 })

	const title = String(body.title ?? '').trim()
	const message = String(body.message ?? '').trim()
	const target = normalizeTarget(body.target)
	const actionLink = body.action_link == null ? null : String(body.action_link).trim() || null
	const isActive = body.is_active == null ? true : Boolean(body.is_active)

	if (!title) return json({ ok: false, error: 'Title is required' }, { status: 400 })
	if (!message) return json({ ok: false, error: 'Message is required' }, { status: 400 })
	if (!target) return json({ ok: false, error: 'Target is required (all, artists, djs, consumers)' }, { status: 400 })

	const payload = {
		title,
		message,
		target,
		action_link: actionLink,
		is_active: isActive,
	}

	const { data, error } = await supabase
		.from(TABLE)
		.insert(payload)
		.select('id,title,message,target,action_link,is_active,created_at')
		.single()

	if (error) {
		if (isMissingTable(error)) {
			return json(
				{
					ok: false,
					error: `Missing table ${TABLE}. Apply migration 20260311120000_announcements.sql then reload the Supabase schema cache.`,
				},
				{ status: 500 },
			)
		}
		return json({ ok: false, error: error.message }, { status: 500 })
	}

	const row = data as unknown as AnnouncementRow

	await logAdminAction({
		ctx,
		action: 'announcements.create',
		target_type: 'announcement',
		target_id: row.id,
		before_state: null,
		after_state: row,
		meta: { module: 'announcements', target },
		req,
	})

	return json({ ok: true, announcement: { id: row.id } })
}
