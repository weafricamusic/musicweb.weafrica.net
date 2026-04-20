import { NextResponse } from 'next/server'

import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function isSchemaMissingError(message: string | undefined): boolean {
	const msg = String(message ?? '')
	return /schema cache|could not find the table|does not exist|PGRST205/i.test(msg)
}

/**
 * Publish an album immediately.
 * - Sets: visibility=public, is_active=true, published_at=now, updated_at=now
 */
export async function POST(_req: Request, { params }: { params: Promise<{ id: string }> }) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_artists')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { id } = await params
	const albumId = String(id ?? '').trim()
	if (!albumId) return json({ error: 'Missing id' }, { status: 400 })

	const nowIso = new Date().toISOString()
	const update = {
		visibility: 'public',
		is_active: true,
		published_at: nowIso,
		updated_at: nowIso,
	}

	const { error } = await supabase.from('albums').update(update).eq('id', albumId)
	if (error) {
		if (isSchemaMissingError(error.message)) {
			return json(
				{ error: "albums table not found. Apply the albums migration, then run: NOTIFY pgrst, 'reload schema';" },
				{ status: 500 },
			)
		}
		return json({ error: error.message }, { status: 500 })
	}

	return json({ ok: true }, { status: 200 })
}
