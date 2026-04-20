import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import type { SupabaseClient } from '@supabase/supabase-js'
import { requestDualApproval } from '@/lib/admin/approvals'
import { getAdminCountryCode } from '@/lib/country/context'

export const runtime = 'nodejs'

type CreateTransactionBody = {
	action: 'create_transaction'
	type: 'coin_purchase' | 'subscription' | 'ad' | 'gift' | 'battle_reward' | 'adjustment'
	actor_id: string | null
	target_type: 'artist' | 'dj' | null
	target_id: string | null
	amount_mwk: string | number
	coins: string | number
	source?: string | null
}

type CreateWithdrawalBody = {
	action: 'create_withdrawal'
	beneficiary_type: 'artist' | 'dj'
	beneficiary_id: string
	amount_mwk: string | number
	method: string
}

type Body = CreateTransactionBody | CreateWithdrawalBody

function asNumber(value: unknown): number {
	if (typeof value === 'number') return value
	if (typeof value === 'string') return Number(value)
	return NaN
}

async function tryLogFinance(
	supabase: SupabaseClient,
	input: {
		admin_email: string | null
		action: string
		target_type: string
		target_id: string
		meta?: Record<string, unknown>
	},
) {
	try {
		await supabase.from('admin_logs').insert({
			admin_email: input.admin_email,
			action: input.action,
			target_type: input.target_type,
			target_id: input.target_id,
			reason: (input.meta as any)?.reason ?? null,
			meta: input.meta ?? {},
		})
	} catch {
		// best-effort
	}
}

export async function POST(req: Request) {
	const adminCtx = await getAdminContext()
	if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
	try { assertPermission(adminCtx, 'can_manage_finance') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

	const supabase = tryCreateSupabaseAdminClient()
	if (!supabase) {
		return NextResponse.json(
			{ error: 'SUPABASE_SERVICE_ROLE_KEY is required for finance tools (RLS is deny-all).' },
			{ status: 500 },
		)
	}

	const body = (await req.json().catch(() => null)) as Body | null
	if (!body || typeof body !== 'object' || !('action' in body)) {
		return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
	}

	if (body.action === 'create_transaction') {
		const country = await getAdminCountryCode().catch(() => 'MW')
		const amount = asNumber(body.amount_mwk)
		const coinCount = asNumber(body.coins)
		const allowNegative = body.type === 'adjustment'
		if (!Number.isFinite(amount) || (!allowNegative && amount < 0)) {
			return NextResponse.json({ error: 'Invalid amount_mwk' }, { status: 400 })
		}
		if (!Number.isFinite(coinCount) || (!allowNegative && coinCount < 0)) {
			return NextResponse.json({ error: 'Invalid coins' }, { status: 400 })
		}

		// Gift/battle must have a target.
		if ((body.type === 'gift' || body.type === 'battle_reward') && (!body.target_type || !body.target_id)) {
			return NextResponse.json({ error: 'gift/battle_reward requires target_type and target_id' }, { status: 400 })
		}

		// For adjustments, require dual approval instead of immediate insert
		if (body.type === 'adjustment') {
			const { id: approvalId } = await requestDualApproval(supabase, adminCtx, {
				action_type: 'finance.transaction.adjustment',
				target_type: body.target_type ?? null,
				target_id: body.target_id ?? null,
				payload: {
					type: body.type,
					actor_id: body.actor_id,
					target_type: body.target_type,
					target_id: body.target_id,
					amount_mwk: amount,
					coins: Math.trunc(coinCount),
					source: (body.source ?? null) || null,
					country_code: country,
					created_by: 'finance_tools',
				},
			})
			await tryLogFinance(supabase, {
				admin_email: adminCtx.admin.email,
				action: 'finance.transaction.approval_requested',
				target_type: body.target_type ?? 'transaction',
				target_id: body.target_id ?? 'unknown',
				meta: { approval_id: approvalId, requested_action: 'adjustment' },
			})
			return NextResponse.json({ ok: true, status: 'pending_approval', approval_id: approvalId })
		}

		const { data, error } = await supabase
			.from('transactions')
			.insert({
				type: body.type,
				actor_type: body.actor_id ? 'user' : 'system',
				actor_id: body.actor_id,
				target_type: body.target_type,
				target_id: body.target_id,
				amount_mwk: amount,
				coins: Math.trunc(coinCount),
				source: (body.source ?? null) || null,
				meta: { created_by: 'finance_tools' },
				country_code: country,
			})
			.select('id')
			.single()

		if (error) return NextResponse.json({ error: error.message }, { status: 500 })

		await tryLogFinance(supabase, {
			admin_email: adminCtx.admin.email,
			action: 'finance.tools.create_transaction',
			target_type: 'transaction',
			target_id: String((data as any).id),
			meta: {
				type: body.type,
				amount_mwk: amount,
				coins: Math.trunc(coinCount),
				target_type: body.target_type,
				target_id: body.target_id,
				source: (body.source ?? null) || null,
			},
		})

		return NextResponse.json({ ok: true, id: (data as any).id })
	}

	if (body.action === 'create_withdrawal') {
		const country = await getAdminCountryCode().catch(() => 'MW')
		const amount = asNumber(body.amount_mwk)
		if (!body.beneficiary_id?.trim()) return NextResponse.json({ error: 'Missing beneficiary_id' }, { status: 400 })
		if (!body.method?.trim()) return NextResponse.json({ error: 'Missing method' }, { status: 400 })
		if (!Number.isFinite(amount) || amount <= 0) return NextResponse.json({ error: 'Invalid amount_mwk' }, { status: 400 })

		const { data, error } = await supabase
			.from('withdrawals')
			.insert({
				beneficiary_type: body.beneficiary_type,
				beneficiary_id: body.beneficiary_id,
				amount_mwk: amount,
				method: body.method,
				status: 'pending',
				meta: { created_by: 'finance_tools' },
				country_code: country,
			})
			.select('id')
			.single()

		if (error) return NextResponse.json({ error: error.message }, { status: 500 })

		await tryLogFinance(supabase, {
			admin_email: adminCtx.admin.email,
			action: 'finance.tools.create_withdrawal',
			target_type: 'withdrawal',
			target_id: String((data as any).id),
			meta: {
				beneficiary_type: body.beneficiary_type,
				beneficiary_id: body.beneficiary_id,
				amount_mwk: amount,
				method: body.method,
			},
		})

		return NextResponse.json({ ok: true, id: (data as any).id })
	}

	return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
