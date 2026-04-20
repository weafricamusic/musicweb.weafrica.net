import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'

export const runtime = 'nodejs'

type Action = 'approve' | 'remove' | 'dismiss'

type Body = {
	action: Action
	confirm?: boolean
	note?: string
}

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(adminCtx, 'can_stop_streams')
	} catch {
		return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
	}

	const { id } = await ctx.params
	if (!id) return NextResponse.json({ error: 'Invalid report id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as Body | null
	if (!body || typeof body !== 'object' || !body.action) return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
	if (body.confirm !== true) return NextResponse.json({ error: 'Confirmation required' }, { status: 400 })

	try {
		const result = await adminBackendFetchJson(`/admin/reports/${encodeURIComponent(id)}/review`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ action: body.action, notes: body.note ?? null }),
		})
		return NextResponse.json(result)
	} catch (error) {
		return NextResponse.json({ error: error instanceof Error ? error.message : 'Action failed' }, { status: 500 })
	}
}
