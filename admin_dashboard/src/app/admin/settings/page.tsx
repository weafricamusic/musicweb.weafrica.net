import Link from 'next/link'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

type AdminRow = {
  id: string
  email: string
  role: string
  status: 'active' | 'suspended'
  created_at: string
  last_login_at: string | null
}

export default async function AdminSettingsPage() {
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

  const supabaseAdmin = tryCreateSupabaseAdminClient()
  if (!supabaseAdmin) {
    return (
      <div className="mx-auto max-w-xl rounded-2xl border border-amber-500/30 bg-amber-500/10 p-6 text-amber-200">
        <h1 className="text-lg font-semibold">Service role required</h1>
        <p className="mt-2 text-sm">Set SUPABASE_SERVICE_ROLE_KEY to manage admins under RLS.</p>
      </div>
    )
  }

  if (ctx.admin.role !== 'super_admin') {
    return (
      <div className="mx-auto max-w-xl rounded-2xl border border-white/10 bg-white/5 p-6 text-center">
        <h1 className="text-lg font-semibold">Access denied</h1>
        <p className="mt-2 text-sm text-gray-400">Only Super Admin can manage admin accounts.</p>
        <div className="mt-4">
          <Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Return to dashboard</Link>
        </div>
      </div>
    )
  }

  const { data, error } = await supabaseAdmin
    .from('admins')
    .select('id,email,role,status,created_at,last_login_at')
    .order('created_at', { ascending: false })
    .limit(200)

  const schemaMissing =
    !!error &&
    (error.code === 'PGRST205' ||
      /schema cache/i.test(error.message ?? '') ||
      /could not find the table/i.test(error.message ?? '') ||
      /relation .*admins.* does not exist/i.test(error.message ?? ''))

  const rows = (data ?? []) as AdminRow[]

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Admin Settings</h1>
          <p className="mt-1 text-sm text-gray-400">Manage admin accounts and roles. Super Admin only.</p>
        </div>
        <Link href="/admin/dashboard" className="inline-flex h-10 items-center rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Back to dashboard</Link>
      </div>

    {schemaMissing ? (
      <div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
        <b>Action needed:</b> RBAC tables are missing in Supabase. Apply the migrations in the
        <code className="mx-1 rounded bg-black/30 px-1">supabase/migrations</code> folder (admins + role_permissions), then reload.
      </div>
    ) : null}

    {error && !schemaMissing ? (
      <div className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">Failed to load admins: {error.message}</div>
    ) : null}

      <section className="rounded-2xl border border-white/10 bg-white/5 p-6">
        <h2 className="text-base font-semibold">Add Admin</h2>
        <p className="mt-1 text-sm text-gray-400">Email must match Firebase login; role is enforced by RBAC.</p>
        <form method="post" action="/api/admin/admins" className="mt-3 flex gap-2">
          <input name="email" placeholder="email@example.com" className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm" />
          <select name="role" className="h-10 rounded-xl border border-white/10 bg-black/20 px-3 text-sm">
            <option value="support_admin">Support Admin</option>
            <option value="operations_admin">Operations Admin</option>
            <option value="finance_admin">Finance Admin</option>
            <option value="super_admin">Super Admin</option>
          </select>
          <button type="submit" className="h-10 rounded-xl border border-white/10 px-4 text-sm hover:bg-white/5">Add</button>
        </form>
      </section>

      <section className="rounded-2xl border border-white/10 bg-white/5 p-6">
        <h2 className="text-base font-semibold">Admin Accounts</h2>
        <div className="mt-3 overflow-auto">
          <table className="w-full min-w-[980px] border-separate border-spacing-0 text-left text-sm">
            <thead>
              <tr className="text-gray-400">
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Email</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Role</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Status</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Created</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Last Login</th>
                <th className="border-b border-white/10 py-3 pr-4 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="border-b border-white/10 py-3 pr-4">{r.email}</td>
                  <td className="border-b border-white/10 py-3 pr-4">{r.role}</td>
                  <td className="border-b border-white/10 py-3 pr-4">{r.status}</td>
                  <td className="border-b border-white/10 py-3 pr-4">{new Date(r.created_at).toLocaleString()}</td>
                  <td className="border-b border-white/10 py-3 pr-4">{r.last_login_at ? new Date(r.last_login_at).toLocaleString() : '—'}</td>
                  <td className="border-b border-white/10 py-3 pr-4">
                    <form method="post" action={`/api/admin/admins/${encodeURIComponent(r.id)}`} className="inline-flex gap-2">
                      <input type="hidden" name="action" value="set_status" />
                      <input type="hidden" name="status" value={r.status === 'active' ? 'suspended' : 'active'} />
                      <button className="h-8 rounded-lg border border-white/10 px-3 text-xs hover:bg-white/5">
                        {r.status === 'active' ? 'Suspend' : 'Activate'}
                      </button>
                    </form>
                    <form method="post" action={`/api/admin/admins/${encodeURIComponent(r.id)}`} className="inline-flex gap-2 ml-2">
                      <input type="hidden" name="action" value="set_role" />
                      <select name="role" className="h-8 rounded-lg border border-white/10 bg-black/20 px-2 text-xs">
                        <option value="support_admin">Support Admin</option>
                        <option value="operations_admin">Operations Admin</option>
                        <option value="finance_admin">Finance Admin</option>
                        <option value="super_admin">Super Admin</option>
                      </select>
                      <button className="h-8 rounded-lg border border-white/10 px-3 text-xs hover:bg-white/5">Change</button>
                    </form>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
// Removed duplicate default export
