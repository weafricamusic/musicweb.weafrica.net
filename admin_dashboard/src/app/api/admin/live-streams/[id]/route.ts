import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { adminBackendFetchJson } from '@/lib/admin/backend'

export const runtime = 'nodejs'

type PatchBody =
	| { action: 'set_status'; status: 'live' | 'ended' }
	| { action: 'stop_stream'; reason?: string }

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_stop_streams') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

	const { id } = await ctx.params
	if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') {
		return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
	}

	if (body.action === 'set_status') {
		if (body.status !== 'ended') {
			return NextResponse.json({ error: 'Only ending a stream is supported.' }, { status: 400 })
		}

		try {
			const result = await adminBackendFetchJson(`/admin/streams/${encodeURIComponent(id)}/stop`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ reason: 'ended from admin dashboard' }),
			})
			return NextResponse.json(result)
		} catch (error) {
			return NextResponse.json({ error: error instanceof Error ? error.message : 'Failed to stop stream' }, { status: 500 })
		}
	}

	if (body.action === 'stop_stream') {
		const reason = (body.reason ?? '').trim() || undefined
		try {
			const result = await adminBackendFetchJson(`/admin/streams/${encodeURIComponent(id)}/stop`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ reason }),
			})
			return NextResponse.json(result)
		} catch (error) {
			return NextResponse.json({ error: error instanceof Error ? error.message : 'Failed to stop stream' }, { status: 500 })
		}
	}

	return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
