import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { approveDualApproval, rejectDualApproval } from '@/lib/admin/approvals'

export const runtime = 'nodejs'

type PatchBody = { action: 'approve' | 'reject' }

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const adminCtx = await getAdminContext()
  if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  try { assertPermission(adminCtx, 'can_manage_finance') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

  const { id } = await ctx.params
  const approvalId = Number(id)
  if (!Number.isFinite(approvalId)) return NextResponse.json({ error: 'Invalid approval id' }, { status: 400 })

  const body = (await req.json().catch(() => null)) as PatchBody | null
  if (!body || !body.action) return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) {
    return NextResponse.json(
      { error: 'SUPABASE_SERVICE_ROLE_KEY is required for approvals (no anon fallback).' },
      { status: 500 },
    )
  }

  if (body.action === 'reject') {
    try {
      await rejectDualApproval(supabase, adminCtx, approvalId)
      return NextResponse.json({ ok: true, status: 'rejected' })
    } catch (e) {
      return NextResponse.json({ error: e instanceof Error ? e.message : 'Approval reject failed' }, { status: 400 })
    }
  }

  // Approve: mark approval row and execute the requested operation
  try {
    const { row } = await approveDualApproval(supabase, adminCtx, approvalId)

    const actionType = String(row.action_type ?? '')
    const payload = (row.payload ?? {}) as Record<string, any>
    const now = new Date().toISOString()

    if (actionType === 'finance.withdrawal.approve') {
      const wid = Number(row.target_id)
      if (!Number.isFinite(wid)) throw new Error('Missing withdrawal id')
      const { error } = await supabase
        .from('withdrawals')
        .update({ status: 'approved', approved_at: payload.approved_at ?? now, admin_email: adminCtx.admin.email })
        .eq('id', wid)
      if (error) throw new Error(error.message)
      return NextResponse.json({ ok: true, status: 'approved' })
    }

    if (actionType === 'finance.withdrawal.mark_paid') {
      const wid = Number(row.target_id)
      if (!Number.isFinite(wid)) throw new Error('Missing withdrawal id')
      const { error } = await supabase
        .from('withdrawals')
        .update({ status: 'paid', paid_at: payload.paid_at ?? now, admin_email: adminCtx.admin.email })
        .eq('id', wid)
      if (error) throw new Error(error.message)
      return NextResponse.json({ ok: true, status: 'paid' })
    }

    if (actionType === 'finance.transaction.adjustment') {
      const amt = Number(payload.amount_mwk)
      const coins = Number(payload.coins)
      if (!Number.isFinite(amt)) throw new Error('Invalid amount_mwk in payload')
      if (!Number.isFinite(coins)) throw new Error('Invalid coins in payload')

      const { data, error } = await supabase
        .from('transactions')
        .insert({
          type: 'adjustment',
          actor_type: payload.actor_id ? 'user' : 'system',
          actor_id: payload.actor_id ?? null,
          target_type: payload.target_type ?? null,
          target_id: payload.target_id ?? null,
          amount_mwk: amt,
          coins: Math.trunc(coins),
          source: (payload.source ?? null) || null,
          meta: { created_by: 'finance_tools', approval_id: approvalId },
          country_code: payload.country_code ?? null,
        })
        .select('id')
        .single()
      if (error) throw new Error(error.message)
      return NextResponse.json({ ok: true, id: (data as any).id })
    }

    return NextResponse.json({ error: `Unsupported approval action_type: ${actionType}` }, { status: 400 })
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : 'Approval execution failed' }, { status: 400 })
  }
}
