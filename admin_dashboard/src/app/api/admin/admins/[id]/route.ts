import { NextResponse } from 'next/server'
import { getAdminContext } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const adminCtx = await getAdminContext()
  if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (adminCtx.admin.role !== 'super_admin') return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await ctx.params
  const form = await req.formData().catch(() => null)
  const action = String(form?.get('action') ?? '')
  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return NextResponse.json({ error: 'Service role is required' }, { status: 500 })

  if (action === 'set_status') {
    const status = String(form?.get('status') ?? '') as 'active' | 'suspended'
    if (status !== 'active' && status !== 'suspended') return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    const { error } = await supabase.from('admins').update({ status }).eq('id', id)
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    return NextResponse.json({ ok: true, status })
  }

  if (action === 'set_role') {
    const role = String(form?.get('role') ?? '')
    const validRoles = ['super_admin', 'operations_admin', 'finance_admin', 'support_admin']
    if (!validRoles.includes(role)) return NextResponse.json({ error: 'Invalid role' }, { status: 400 })
    const { error } = await supabase.from('admins').update({ role }).eq('id', id)
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    return NextResponse.json({ ok: true, role })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
