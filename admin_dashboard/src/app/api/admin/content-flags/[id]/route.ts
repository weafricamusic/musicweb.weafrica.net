import { NextResponse } from 'next/server'

import { adminBackendFetchJson } from '@/lib/admin/backend'
import { getAdminContext, assertPermission } from '@/lib/admin/session'

export const runtime = 'nodejs'

type PatchBody = {
	action: 'dismiss' | 'remove'
	notes?: string
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
	if (!id) return NextResponse.json({ error: 'Invalid flag id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body?.action) return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

	try {
		const result = await adminBackendFetchJson(`/admin/content/flags/${encodeURIComponent(id)}/resolve`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ action: body.action, notes: body.notes ?? null }),
		})
		return NextResponse.json(result)
	} catch (error) {
		return NextResponse.json({ error: error instanceof Error ? error.message : 'Failed to resolve flag' }, { status: 500 })
	}
}