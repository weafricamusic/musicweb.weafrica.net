import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { getSupabaseServerEnvDebug, createSupabaseServerClient } from '@/lib/supabase/server'

export const runtime = 'nodejs'

function getErrorMeta(err: unknown): { code?: string; status?: number; message?: string } {
	if (!err || typeof err !== 'object') return {}
	const e = err as Record<string, unknown>
	return {
		code: typeof e.code === 'string' ? e.code : undefined,
		status: typeof e.status === 'number' ? e.status : undefined,
		message: typeof e.message === 'string' ? e.message : undefined,
	}
}

export async function GET() {
	const ctx = await getAdminContext()
	if (!ctx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

	const env = (() => {
		try {
			return getSupabaseServerEnvDebug()
		} catch (e) {
			return { error: e instanceof Error ? e.message : 'Failed to read env' }
		}
	})()

	const supabase = createSupabaseServerClient()

	const viewProbe = await supabase
		.from('current_legal_documents')
		.select('doc_key,slug,audience,language,title,version,published,effective_at,updated_at')
		.order('doc_key', { ascending: true })
		.limit(50)

	const viewMeta = getErrorMeta(viewProbe.error)

	let fallback: any = null
	let fallbackMeta: ReturnType<typeof getErrorMeta> | null = null
	if (viewProbe.error) {
		const res = await supabase
			.from('legal_documents')
			.select('doc_key,slug,audience,language,title,version,published,effective_at,updated_at')
			.eq('published', true)
			.order('doc_key', { ascending: true })
			.limit(50)
		fallback = res.data ?? null
		fallbackMeta = getErrorMeta(res.error)
	}

	return NextResponse.json({
		viewer: { email: ctx.admin.email, role: ctx.admin.role },
		env,
		probe: {
			current_legal_documents: viewProbe.error
				? { ok: false, code: viewMeta.code, status: viewMeta.status, message: viewProbe.error.message }
				: { ok: true, rows: viewProbe.data ?? [] },
			legal_documents_fallback: viewProbe.error
				? fallbackMeta && fallbackMeta.message
					? { ok: false, code: fallbackMeta.code, status: fallbackMeta.status, message: fallbackMeta.message }
					: { ok: true, rows: fallback ?? [] }
				: { skipped: true },
		},
	})
}
