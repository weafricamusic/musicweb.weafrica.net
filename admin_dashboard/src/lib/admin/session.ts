import 'server-only'

import { cookies } from 'next/headers'
import { getFirebaseAdminAuth } from '@/lib/firebase/admin'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { isAdminEmailAllowed } from '@/lib/admin/allowlist'
import type { AdminContext, AdminPermissions, AdminRecord, AdminRole } from './types'

const FIREBASE_SESSION_COOKIE = 'firebase_session'

async function getDecodedFirebase(): Promise<import('firebase-admin/auth').DecodedIdToken | null> {
  const cookieStore = await cookies()
  const session = cookieStore.get(FIREBASE_SESSION_COOKIE)?.value
  if (!session) return null
  try {
    const auth = getFirebaseAdminAuth()
    const decoded = await auth.verifySessionCookie(session, true)
    const record = await auth.getUser(decoded.uid)
    if (record.disabled) return null
    return decoded
  } catch {
    return null
  }
}

function mapProfilesPermissions(role: string, permissions: Record<string, unknown> | null | undefined): AdminPermissions {
  const all = permissions?.all === true || role === 'super_admin'
  const dashboard = all || permissions?.dashboard === true
  const users = all || permissions?.users === true || permissions?.users_view === true
  const moderate = all || permissions?.moderate === true || permissions?.content === true
  const finance = all || permissions?.finance === true
  const admin = all || permissions?.admin === true || role === 'super_admin'

  return {
    can_manage_users: users,
    can_manage_artists: users || moderate,
    can_manage_djs: users || moderate,
    can_manage_finance: finance,
    can_stop_streams: moderate,
    can_manage_admins: admin,
    can_view_logs: dashboard || admin,
    can_manage_events: moderate,
  }
}

export async function getAdminContext(): Promise<AdminContext | null> {
  const firebase = await getDecodedFirebase()
  if (!firebase) return null

  const email = (firebase.email ?? '').trim().toLowerCase()
  if (!email) return null

	const allowlisted = isAdminEmailAllowed(email)

  // Prefer service-role for server-side RBAC lookups (tables are RLS-denied by default).
  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) {
    // Fail closed: without service-role we can't safely read RBAC tables.
    // The calling UI can surface a setup error (service role required).
    return null
  }

  const ADMIN_SELECT =
    'id,uid,email,role,status,created_at,last_login_at,can_manage_users,can_manage_artists,can_manage_djs,can_manage_finance,can_stop_streams,can_manage_admins,can_view_logs,can_manage_events' as const

  const { data: adminRow, error: adminError } = await supabase
    .from('admins_with_permissions')
    .select(ADMIN_SELECT)
    .eq('email', email)
    .limit(1)
    .maybeSingle()

  // If this Supabase project hasn't applied our admins/permissions migrations yet,
  // PostgREST returns "schema cache" errors. Fall back to the legacy schema used
  // by some WeAfrica projects: public.app_admins keyed by Firebase uid.
  const schemaMissing =
    !!adminError &&
    (adminError.code === 'PGRST205' ||
      /schema cache/i.test(adminError.message ?? '') ||
      /could not find the table/i.test(adminError.message ?? ''))

  if (adminError && !schemaMissing) return null

  // Bootstrap: if RBAC schema exists but the admin record is missing, allowlisted
  // emails can auto-create their admin row on first login.
  if (!adminError && !adminRow && allowlisted) {
    try {
      await supabase
        .from('admins')
        .upsert(
          {
            email,
            uid: firebase.uid,
            role: 'super_admin',
            status: 'active',
          },
          { onConflict: 'email' },
        )
      const { data: bootRow } = await supabase
        .from('admins_with_permissions')
        .select(ADMIN_SELECT)
        .eq('email', email)
        .limit(1)
        .maybeSingle()
      if (bootRow) {
        const admin: AdminRecord = {
          id: String(bootRow.id),
          uid: bootRow.uid ?? null,
          email: bootRow.email,
          role: bootRow.role as AdminRole,
          status: bootRow.status,
          created_at: bootRow.created_at,
          last_login_at: bootRow.last_login_at ?? null,
        }

        const permissions: AdminPermissions = {
          can_manage_users: !!bootRow.can_manage_users,
          can_manage_artists: !!bootRow.can_manage_artists,
          can_manage_djs: !!bootRow.can_manage_djs,
          can_manage_finance: !!bootRow.can_manage_finance,
          can_stop_streams: !!bootRow.can_stop_streams,
          can_manage_admins: !!bootRow.can_manage_admins,
          can_view_logs: !!bootRow.can_view_logs,
          can_manage_events: !!(bootRow as any).can_manage_events,
        }
        return { firebase, admin, permissions }
      }
    } catch {
      // ignore; will fall through to schemaMissing/legacy logic
    }
  }

  if (!adminError && adminRow) {
    if (adminRow.status !== 'active') return null

    const admin: AdminRecord = {
      id: String(adminRow.id),
      uid: adminRow.uid ?? null,
      email: adminRow.email,
      role: adminRow.role as AdminRole,
      status: adminRow.status,
      created_at: adminRow.created_at,
      last_login_at: adminRow.last_login_at ?? null,
    }

    const permissions: AdminPermissions = {
      can_manage_users: !!adminRow.can_manage_users,
      can_manage_artists: !!adminRow.can_manage_artists,
      can_manage_djs: !!adminRow.can_manage_djs,
      can_manage_finance: !!adminRow.can_manage_finance,
      can_stop_streams: !!adminRow.can_stop_streams,
      can_manage_admins: !!adminRow.can_manage_admins,
      can_view_logs: !!adminRow.can_view_logs,
      can_manage_events: !!(adminRow as any).can_manage_events,
    }

    // best-effort: update last_login_at
    try {
      await supabase
        .from('admins')
        .update({ last_login_at: new Date().toISOString(), uid: firebase.uid })
        .eq('id', admin.id)
    } catch {
      // ignore
    }

    return { firebase, admin, permissions }
  }

  // New Phase-5 path: profiles-based admin model.
  const { data: profileRow, error: profileError } = await supabase
    .from('profiles')
    .select('id,email,is_admin,admin_role,status,created_at,updated_at')
    .eq('id', firebase.uid)
    .limit(1)
    .maybeSingle()

  if (!profileError && profileRow?.is_admin === true) {
    const roleName = String(profileRow.admin_role ?? 'viewer').trim().toLowerCase() as AdminRole
    const { data: roleRow } = await supabase
      .from('admin_role_permissions')
      .select('permissions')
      .eq('role_name', roleName)
      .limit(1)
      .maybeSingle()

    const admin: AdminRecord = {
      id: String(profileRow.id),
      uid: firebase.uid,
      email: String(profileRow.email ?? email),
      role: roleName,
      status: (String(profileRow.status ?? 'active') as AdminRecord['status']),
      created_at: String(profileRow.created_at ?? profileRow.updated_at ?? new Date().toISOString()),
      last_login_at: null,
    }

    if (admin.status !== 'active') return null

    const permissions = mapProfilesPermissions(roleName, (roleRow?.permissions ?? null) as Record<string, unknown> | null)
    return { firebase, admin, permissions }
  }

  // Legacy fallback: app_admins { user_id (text), role (text) }
  const { data: legacyRow, error: legacyError } = await supabase
    .from('app_admins')
    .select('user_id,role,added_at')
    .eq('user_id', firebase.uid)
    .limit(1)
    .maybeSingle()

  if (legacyError || !legacyRow) {
    // Fail closed: require RBAC schema or an explicit legacy admin record.
    return null
  }

  function normalizeLegacyRole(raw: unknown): AdminRole {
    const v = String(raw ?? '')
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '_')
      .replace(/-+/g, '_')

    if (!v) return 'support_admin'

    // super
    if (v === 'super_admin' || v === 'superadmin' || v === 'super' || v === 'admin') return 'super_admin'

    // operations
    if (
      v === 'operations_admin' ||
      v === 'ops_admin' ||
      v === 'ops' ||
      v === 'operations' ||
      v === 'operator' ||
      v === 'operations_manager'
    ) {
      return 'operations_admin'
    }

    // finance
    if (v === 'finance_admin' || v === 'finance' || v === 'payments_admin' || v === 'payment_admin') return 'finance_admin'

    // support
    if (v === 'support_admin' || v === 'support' || v === 'moderator' || v === 'mod' || v === 'customer_support') return 'support_admin'

    return 'support_admin'
  }

  const legacyRole = normalizeLegacyRole(legacyRow.role)
  const permissionsByRole: Record<AdminRole, AdminPermissions> = {
    super_admin: {
      can_manage_users: true,
      can_manage_artists: true,
      can_manage_djs: true,
      can_manage_finance: true,
      can_stop_streams: true,
      can_manage_admins: true,
      can_view_logs: true,
      can_manage_events: true,
    },
    operations_admin: {
      can_manage_users: true,
      can_manage_artists: true,
      can_manage_djs: true,
      can_manage_finance: false,
      can_stop_streams: true,
      can_manage_admins: false,
      can_view_logs: true,
      can_manage_events: true,
    },
    finance_admin: {
      can_manage_users: false,
      can_manage_artists: false,
      can_manage_djs: false,
      can_manage_finance: true,
      can_stop_streams: false,
      can_manage_admins: false,
      can_view_logs: true,
      can_manage_events: true,
    },
    support_admin: {
      can_manage_users: false,
      can_manage_artists: false,
      can_manage_djs: false,
      can_manage_finance: false,
      can_stop_streams: false,
      can_manage_admins: false,
      can_view_logs: true,
      can_manage_events: false,
    },
    viewer: {
      can_manage_users: false,
      can_manage_artists: false,
      can_manage_djs: false,
      can_manage_finance: false,
      can_stop_streams: false,
      can_manage_admins: false,
      can_view_logs: true,
      can_manage_events: false,
    },
    moderator: {
      can_manage_users: true,
      can_manage_artists: true,
      can_manage_djs: true,
      can_manage_finance: false,
      can_stop_streams: true,
      can_manage_admins: false,
      can_view_logs: true,
      can_manage_events: true,
    },
    admin: {
      can_manage_users: true,
      can_manage_artists: true,
      can_manage_djs: true,
      can_manage_finance: true,
      can_stop_streams: true,
      can_manage_admins: true,
      can_view_logs: true,
      can_manage_events: true,
    },
  }

  const admin: AdminRecord = {
    id: String(legacyRow.user_id),
    uid: firebase.uid,
    email,
    role: legacyRole,
    status: 'active',
    created_at: legacyRow.added_at ?? new Date().toISOString(),
    last_login_at: null,
  }

  const permissions = permissionsByRole[legacyRole] ?? permissionsByRole.support_admin
  return { firebase, admin, permissions }
}

export async function requireAdminContext(): Promise<AdminContext> {
  const ctx = await getAdminContext()
  if (!ctx) throw new Error('Unauthorized')
  return ctx
}

export function hasPermission(ctx: AdminContext, perm: keyof AdminPermissions): boolean {
  return Boolean(ctx.permissions[perm])
}

export function assertPermission(ctx: AdminContext, perm: keyof AdminPermissions) {
  if (!hasPermission(ctx, perm)) {
    const error = new Error('Forbidden') as Error & { statusCode?: number }
    error.statusCode = 403
    throw error
  }
}
