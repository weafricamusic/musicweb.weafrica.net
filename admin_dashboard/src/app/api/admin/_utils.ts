import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

export function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function requireAdmin() {
	const ctx = await getAdminContext()
	if (!ctx) return { ctx: null, res: json({ error: 'Unauthorized' }, { status: 401 }) } as const
	return { ctx, res: null } as const
}

export async function notImplemented(resource: string) {
	const { res } = await requireAdmin()
	if (res) return res
	if (process.env.NODE_ENV === 'production') {
		return json({ error: 'Not found' }, { status: 404 })
	}
	return json({ error: 'Not implemented', resource }, { status: 501 })
}
