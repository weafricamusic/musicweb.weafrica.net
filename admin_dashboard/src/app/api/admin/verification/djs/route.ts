import { json, requireAdmin } from '../../_utils'
import { assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type Bucket = 'pending' | 'approved' | 'rejected'

type DjRow = {
	id: string
	dj_name: string | null
	approved: boolean
	status: 'pending' | 'active' | 'blocked'
	blocked: boolean
	created_at: string
}

function normalizeCreatorStatus(input: { approved?: boolean | null; status?: string | null; blocked?: boolean | null }):
	| 'pending'
	| 'active'
	| 'blocked' {
	if (input.blocked === true) return 'blocked'
	if (input.status === 'blocked') return 'blocked'
	if (input.status === 'active') return 'active'
	if (input.approved === true) return 'active'
	return 'pending'
}

function bucketMatches(bucket: Bucket, normalized: 'pending' | 'active' | 'blocked'): boolean {
	if (bucket === 'pending') return normalized === 'pending'
	if (bucket === 'approved') return normalized === 'active'
	return normalized === 'blocked'
}

export async function GET(req: Request) {
	const { ctx, res } = await requireAdmin()
	if (res) return res
	try {
		assertPermission(ctx, 'can_manage_djs')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const url = new URL(req.url)
	const bucket = (url.searchParams.get('bucket') ?? 'pending') as Bucket
	if (bucket !== 'pending' && bucket !== 'approved' && bucket !== 'rejected') {
		return json({ error: 'Invalid bucket' }, { status: 400 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for admin actions (no anon fallback).' },
			{ status: 500 },
		)
	}

	let data: any[] | null = null
	let error: any = null
	;({ data, error } = await supabase
		.from('djs')
		.select('id,dj_name,approved,status,blocked,created_at')
		.order('created_at', { ascending: false })
		.limit(200))
	if (error) {
		;({ data, error } = await supabase
			.from('djs')
			.select('id,dj_name,approved,created_at')
			.order('created_at', { ascending: false })
			.limit(200))
	}
	if (error) return json({ error: error.message ?? 'Query failed' }, { status: 500 })

	const rows = (data ?? []) as Array<{
		id: string
		dj_name?: string | null
		approved?: boolean | null
		status?: string | null
		blocked?: boolean | null
		created_at: string
	}>

	const items: DjRow[] = rows
		.map((d) => {
			const normalized = normalizeCreatorStatus(d)
			return {
				id: d.id,
				dj_name: d.dj_name ?? null,
				approved: d.approved === true,
				status: normalized,
				blocked: d.blocked === true || normalized === 'blocked',
				created_at: d.created_at,
			}
		})
		.filter((r) => bucketMatches(bucket, r.status))

	return json({ ok: true, bucket, items })
}
