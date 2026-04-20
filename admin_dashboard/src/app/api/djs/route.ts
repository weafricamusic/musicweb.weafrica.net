import { NextRequest, NextResponse } from 'next/server'
import { tryCreateSupabasePublicClient } from '@/lib/supabase/public'

export const runtime = 'nodejs'

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

function clampInt(raw: string | null, fallback: number, min: number, max: number): number {
	if (!raw) return fallback
	const n = Number(raw)
	if (!Number.isFinite(n)) return fallback
	return Math.max(min, Math.min(max, Math.trunc(n)))
}

export async function GET(req: NextRequest) {
	const supabase = tryCreateSupabasePublicClient()
	if (!supabase) return json({ error: 'Server not configured (missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY).' }, { status: 500 })

	const url = req.nextUrl
	const q = (url.searchParams.get('q') ?? '').trim()
	const limit = clampInt(url.searchParams.get('limit'), 50, 1, 200)
	const offset = clampInt(url.searchParams.get('offset'), 0, 0, 10_000)
	const rangeTo = offset + limit - 1

	const attempts: Array<{
		select: string
		filters: Array<'approved' | 'status' | 'blocked'>
	}> = [
		{
			select: 'id,dj_name,avatar_url,bio,country,approved,status,blocked,created_at',
			filters: ['approved', 'status', 'blocked'],
		},
		{
			select: 'id,dj_name,approved,status,blocked,created_at',
			filters: ['approved', 'status', 'blocked'],
		},
		{
			select: 'id,dj_name,approved,created_at',
			filters: ['approved'],
		},
		{
			select: 'id,dj_name,created_at',
			filters: [],
		},
	]

	let lastError: unknown = null
	for (const a of attempts) {
		let query = supabase
			.from('djs')
			.select(a.select)
			.order('created_at', { ascending: false })
			.range(offset, rangeTo)

		if (q) query = query.ilike('dj_name', `%${q}%`)

		if (a.filters.includes('approved')) query = query.eq('approved', true)
		if (a.filters.includes('status')) query = query.eq('status', 'active')
		if (a.filters.includes('blocked')) query = query.eq('blocked', false)

		const { data, error } = await query
		if (!error) {
			return NextResponse.json(
				{ ok: true, djs: data ?? [], limit, offset },
				{ headers: { 'cache-control': 'no-store' } },
			)
		}
		lastError = error
	}

	return json({ error: (lastError as any)?.message ?? 'Query failed' }, { status: 500 })
}
