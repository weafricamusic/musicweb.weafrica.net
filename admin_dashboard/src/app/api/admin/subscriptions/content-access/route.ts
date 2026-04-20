import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { asSubscriptionPlanId } from '@/lib/subscription/plans'
import { logAdminAction } from '@/lib/admin/audit'

export const runtime = 'nodejs'

type Row = {
	plan_id: string
	rules: Record<string, unknown>
	created_at: string
	updated_at: string
}

function mapSupabaseError(err: any): string {
	const message = String(err?.message ?? 'Unknown error')
	const code = String(err?.code ?? '')
	const isMissingTable =
		code === '42P01' ||
		code === 'PGRST106' ||
		message.includes("Could not find the table 'public.subscription_content_access'") ||
		message.toLowerCase().includes('schema cache')

	if (isMissingTable) {
		return [
			"Missing table: public.subscription_content_access.",
			"Apply the migration supabase/migrations/20260114130000_subscriptions_admin_setup.sql to your Supabase project, then reload the schema cache (SQL: NOTIFY pgrst, 'reload schema';).",
		].join(' ')
	}

	return message
}

function json(data: unknown, init?: ResponseInit) {
	return NextResponse.json(data, init)
}

export async function GET() {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const { data, error } = await supabase
		.from('subscription_content_access')
		.select('plan_id,rules,created_at,updated_at')
		.order('plan_id', { ascending: true })

	if (error) return json({ error: mapSupabaseError(error) }, { status: 500 })
	return json({ ok: true, rows: (data ?? []) as unknown as Row[] })
}

type PatchBody = {
	plan_id: string
	rules: Record<string, unknown>
}

export async function PUT(req: Request) {
	const ctx = await getAdminContext()
	if (!ctx) return json({ error: 'Unauthorized' }, { status: 401 })
	try {
		assertPermission(ctx, 'can_manage_finance')
	} catch {
		return json({ error: 'Forbidden' }, { status: 403 })
	}

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) return json({ error: 'SUPABASE_SERVICE_ROLE_KEY is required.' }, { status: 500 })

	const body = (await req.json().catch(() => null)) as PatchBody | null
	if (!body || typeof body !== 'object') return json({ error: 'Invalid body' }, { status: 400 })

	const planId = asSubscriptionPlanId(body.plan_id)
	if (!planId) return json({ error: 'Invalid plan_id' }, { status: 400 })
	if (!body.rules || typeof body.rules !== 'object') return json({ error: 'rules must be an object' }, { status: 400 })

	const { data: before } = await supabase
		.from('subscription_content_access')
		.select('plan_id,rules')
		.eq('plan_id', planId)
		.maybeSingle()

	const nowIso = new Date().toISOString()
	const { data: updated, error } = await supabase
		.from('subscription_content_access')
		.upsert({ plan_id: planId, rules: body.rules, updated_at: nowIso }, { onConflict: 'plan_id' })
		.select('plan_id,rules,created_at,updated_at')
		.single()

	if (error) return json({ error: mapSupabaseError(error) }, { status: 500 })

	await logAdminAction({
		ctx,
		action: 'subscription_content_access.update',
		target_type: 'subscription_plan',
		target_id: planId,
		before_state: (before ?? null) as any,
		after_state: (updated ?? null) as any,
		meta: { module: 'subscriptions' },
		req,
	})

	return json({ ok: true, row: updated as unknown as Row })
}
