import { NextResponse } from 'next/server'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

export async function POST(req: Request) {
  const ctx = await getAdminContext()
  if (!ctx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  // Only Super Admin can add admins
  if (ctx.admin.role !== 'super_admin') return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return NextResponse.json({ error: 'Service role is required' }, { status: 500 })

  const form = await req.formData().catch(() => null)
  const email = String(form?.get('email') ?? '').trim().toLowerCase()
  const role = String(form?.get('role') ?? '').trim()
  const validRoles = ['super_admin', 'operations_admin', 'finance_admin', 'support_admin']
  if (!email || !validRoles.includes(role)) return NextResponse.json({ error: 'Invalid email or role' }, { status: 400 })

  const { error } = await supabase.from('admins').upsert({ email, role, status: 'active' }, { onConflict: 'email' })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
