import 'server-only'

import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import type { AdminContext } from './types'
import { getAdminCountryCode } from '@/lib/country/context'

type LogInput = {
  ctx: AdminContext
  action: string
  target_type: string
  target_id: string
  before_state?: Record<string, unknown> | null
  after_state?: Record<string, unknown> | null
  meta?: Record<string, unknown> | null
}

export async function logAdminAction(input: LogInput & { req?: Request }) {
  const supabaseAdmin = tryCreateSupabaseAdminClient()
  if (!supabaseAdmin) return
  const supabase = supabaseAdmin
  const country = await getAdminCountryCode().catch(() => 'MW')
  const ip = input.req ? (input.req.headers.get('x-forwarded-for') ?? input.req.headers.get('x-real-ip')) : null
  const ua = input.req ? input.req.headers.get('user-agent') : null

  const auditPayload = {
    admin_id: input.ctx.admin.id,
    admin_email: input.ctx.admin.email,
    action: input.action,
    target_type: input.target_type,
    target_id: input.target_id,
    before_state: input.before_state ?? null,
    after_state: input.after_state ?? null,
    ip_address: ip,
    user_agent: ua,
  }

  try {
    await supabase.from('admin_activity').insert({
      actor_uid: input.ctx.firebase.uid,
      action: input.action,
      entity: input.target_type,
      entity_id: input.target_id,
      meta: input.meta ?? {},
    })
  } catch {
    // ignore
  }

  try {
    const { error: rpcError } = await supabase.rpc('log_admin_action', {
      p_admin_id: auditPayload.admin_id,
      p_admin_email: auditPayload.admin_email,
      p_action: auditPayload.action,
      p_target_type: auditPayload.target_type,
      p_target_id: auditPayload.target_id,
      p_before_state: auditPayload.before_state,
      p_after_state: auditPayload.after_state,
      p_ip_address: ip,
      p_user_agent: ua,
    })
    if (rpcError) {
      try {
        await supabase.from('admin_audit_logs').insert(auditPayload as any)
      } catch {
        // Fallback: at least write to the basic admin_logs table.
        await supabase.from('admin_logs').insert({
          admin_email: input.ctx.admin.email,
          action: input.action,
          target_type: input.target_type,
          target_id: input.target_id,
          meta: {
            before_state: input.before_state ?? null,
            after_state: input.after_state ?? null,
            country,
            admin_role: input.ctx.admin.role,
            ...(input.meta ?? {}),
          },
        })
      }
    }
  } catch {
    // ignore
  }
}
 
