import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'
import type { AdminContext } from './types'

export type DualApprovalPayload = {
  action_type: string
  target_type?: string | null
  target_id?: string | null
  payload?: Record<string, unknown> | null
}

export async function requestDualApproval(
  supabase: SupabaseClient,
  ctx: AdminContext,
  input: DualApprovalPayload,
): Promise<{ id: number }> {
  const { data, error } = await supabase
    .from('admin_dual_approvals')
    .insert({
      action_type: input.action_type,
      target_type: input.target_type ?? null,
      target_id: input.target_id ?? null,
      payload: input.payload ?? {},
      status: 'pending',
      requested_by_admin_id: ctx.admin.id,
    })
    .select('id')
    .single()

  if (error) throw new Error(error.message)
  return { id: Number((data as any).id) }
}

export async function approveDualApproval(
  supabase: SupabaseClient,
  ctx: AdminContext,
  id: number,
): Promise<{ row: any }> {
  const { data: row, error } = await supabase
    .from('admin_dual_approvals')
    .select('*')
    .eq('id', id)
    .maybeSingle()
  if (error) throw new Error(error.message)
  if (!row) throw new Error('Approval not found')
  if (row.status !== 'pending') throw new Error('Approval is not pending')
  if (row.requested_by_admin_id === ctx.admin.id) throw new Error('Requester cannot approve their own request')

  const now = new Date().toISOString()
  const { error: updateErr } = await supabase
    .from('admin_dual_approvals')
    .update({ status: 'approved', approved_by_admin_id: ctx.admin.id, decided_at: now })
    .eq('id', id)
  if (updateErr) throw new Error(updateErr.message)
  return { row }
}

export async function rejectDualApproval(
  supabase: SupabaseClient,
  ctx: AdminContext,
  id: number,
): Promise<void> {
  const { data: row, error } = await supabase
    .from('admin_dual_approvals')
    .select('requested_by_admin_id,status')
    .eq('id', id)
    .maybeSingle()
  if (error) throw new Error(error.message)
  if (!row) throw new Error('Approval not found')
  if (row.status !== 'pending') throw new Error('Approval is not pending')

  const now = new Date().toISOString()
  const { error: updateErr } = await supabase
    .from('admin_dual_approvals')
    .update({ status: 'rejected', approved_by_admin_id: ctx.admin.id, decided_at: now })
    .eq('id', id)
  if (updateErr) throw new Error(updateErr.message)
}
