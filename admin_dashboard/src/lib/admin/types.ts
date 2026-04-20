import type { DecodedIdToken } from 'firebase-admin/auth'

export type AdminRole = 'super_admin' | 'operations_admin' | 'finance_admin' | 'support_admin'
  | 'viewer'
  | 'moderator'
  | 'admin'

export type AdminPermissions = {
  can_manage_users: boolean
  can_manage_artists: boolean
  can_manage_djs: boolean
  can_manage_finance: boolean
  can_stop_streams: boolean
  can_manage_admins: boolean
  can_view_logs: boolean
  can_manage_events: boolean
}

export type AdminRecord = {
  id: string
  uid: string | null
  email: string
  role: AdminRole
  status: 'active' | 'suspended' | 'banned'
  created_at: string
  last_login_at: string | null
}

export type AdminContext = {
  firebase: DecodedIdToken
  admin: AdminRecord
  permissions: AdminPermissions
}
