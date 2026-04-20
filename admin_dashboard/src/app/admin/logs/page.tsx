import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminContext } from '@/lib/admin/session'
import ServiceRoleRequired from '@/components/admin/ServiceRoleRequired'

export const runtime = 'nodejs'

function isMissingAuditTable(err: any): boolean {
  const message = String(err?.message ?? '')
  const code = String(err?.code ?? '')
  return (
    code === '42P01' ||
    code === 'PGRST106' ||
    message.includes("Could not find the table 'public.admin_audit_logs'") ||
    message.toLowerCase().includes('schema cache')
  )
}

export default async function AdminLogsPage(props: { searchParams?: Promise<{ admin?: string; from?: string; to?: string }> }) {
  const ctx = await getAdminContext()
  if (!ctx) {
    return (
      <div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
        <h1 className="text-lg font-semibold">Access denied</h1>
        <p className="mt-2 text-sm text-gray-400">You are not an active admin.</p>
        <div className="mt-4">
          <Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
        </div>
      </div>
    )
  }

  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return <ServiceRoleRequired title="Service role required for admin logs" />
  const sp = (props.searchParams ? await props.searchParams : {}) ?? {}
  const adminFilter = (sp.admin ?? '').trim().toLowerCase()
  const from = sp.from ? new Date(sp.from) : null
  const to = sp.to ? new Date(sp.to) : null

  // Prefer the richer audit table if present; fall back to admin_logs for older deployments.
  let data: any[] | null = null
  let error: any = null
  try {
    let q = supabase
      .from('admin_audit_logs')
      .select('id,admin_email,action,target_type,target_id,before_state,after_state,created_at,ip_address')
      .order('created_at', { ascending: false })
      .limit(500)
    if (adminFilter) q = q.ilike('admin_email', `%${adminFilter}%`)
    if (from) q = q.gte('created_at', from.toISOString())
    if (to) q = q.lte('created_at', to.toISOString())
    ;({ data, error } = await q)
  } catch (e) {
    error = e
  }

  if (error && isMissingAuditTable(error)) {
    // Minimal fallback: admin_logs (meta may contain before/after/country/role).
    let q = supabase
      .from('admin_logs')
      .select('id,admin_email,action,target_type,target_id,meta,created_at')
      .order('created_at', { ascending: false })
      .limit(500)
    if (adminFilter) q = q.ilike('admin_email', `%${adminFilter}%`)
    if (from) q = q.gte('created_at', from.toISOString())
    if (to) q = q.lte('created_at', to.toISOString())
    const fallback = await q
    data = (fallback.data ?? []) as any
    error = fallback.error
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Admin Logs</h1>
          <p className="mt-1 text-sm text-gray-400">Read-only audit trail: email, role, action, target, country, timestamp.</p>
        </div>
        <Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">
          Back to dashboard
        </Link>
      </div>

      {error ? (
        <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
          Failed to load logs: {error.message}
        </div>
      ) : null}

      <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
        <div className="mb-4 flex gap-3">
          <form method="get" className="flex gap-2">
            <input name="admin" placeholder="Filter admin email" defaultValue={adminFilter} className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
            <input name="from" type="date" className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
            <input name="to" type="date" className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
            <button type="submit" className="h-10 rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Apply</button>
          </form>
        </div>
        <div className="overflow-auto">
          <table className="w-full min-w-[1100px] border-separate border-spacing-0 text-left text-sm">
            <thead>
              <tr className="text-gray-400">
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Admin</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Role</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Action</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Target</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Country</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">IP</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Time</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Diff</th>
              </tr>
            </thead>
            <tbody>
              {(data ?? []).length ? (
                (data ?? []).map((l: any) => {
                  const meta = (l as any)?.meta && typeof (l as any).meta === 'object' ? (l as any).meta : null
                  const before = (l as any).before_state ?? meta?.before_state ?? null
                  const after = (l as any).after_state ?? meta?.after_state ?? null
                  const role = (l as any).admin_role ?? meta?.admin_role ?? '—'
                  const country = (l as any).country ?? meta?.country ?? '—'
                  const ip = (l as any).ip_address ?? '—'
                  const createdAt = (l as any).created_at
                  return (
                  <tr key={l.id}>
                    <td className="border-b border-white/10 py-3 pr-4">{l.admin_email ?? '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{role}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{l.action}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{l.target_type}:{l.target_id}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{country}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{ip}</td>
                    <td className="border-b border-white/10 py-3 pr-4">{createdAt ? new Date(createdAt).toLocaleString() : '—'}</td>
                    <td className="border-b border-white/10 py-3 pr-4">
                      <pre className="max-w-[420px] overflow-auto whitespace-pre-wrap text-xs text-gray-300">
                        {JSON.stringify({ before, after }, null, 2)}
                      </pre>
                    </td>
                  </tr>
                  )
                })
              ) : (
                <tr>
                  <td colSpan={8} className="py-6 text-sm text-gray-400">No admin logs yet.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
