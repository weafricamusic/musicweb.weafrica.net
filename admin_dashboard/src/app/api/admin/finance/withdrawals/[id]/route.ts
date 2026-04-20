import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'

export const runtime = 'nodejs'

type PatchBody = { action: 'approve' | 'reject' | 'mark_paid' }

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_manage_finance') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

	const { id } = await ctx.params
	if (!id) return NextResponse.json({ error: 'Invalid withdrawal id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || !body.action) return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

	try {
		const result = await adminBackendFetchJson(`/admin/finance/withdrawals/${encodeURIComponent(id)}/process`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ action: body.action }),
		})
		return NextResponse.json(result)
	} catch (error) {
		return NextResponse.json({ error: error instanceof Error ? error.message : 'Failed to process withdrawal' }, { status: 500 })
	}
}
