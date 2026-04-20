import 'server-only'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'
import { getAdminCountryCode } from '@/lib/country/context'

export type NewTransaction = {
  type: 'coin_purchase' | 'subscription' | 'ad' | 'gift' | 'battle_reward' | 'adjustment'
  actor_id?: string | null
  actor_type?: 'user' | 'admin' | 'system'
  target_type?: 'artist' | 'dj' | null
  target_id?: string | null
  amount_mwk?: number
  coins?: number
  source?: string | null
  meta?: Record<string, any>
}

export async function addTransaction(tx: NewTransaction): Promise<{ ok: boolean; error?: string }> {
  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return { ok: false, error: 'service-role missing' }
  const country = await getAdminCountryCode()
  const payload = {
    type: tx.type,
    actor_id: tx.actor_id ?? null,
    actor_type: tx.actor_type ?? 'user',
    target_type: tx.target_type ?? null,
    target_id: tx.target_id ?? null,
    amount_mwk: tx.amount_mwk ?? 0,
    coins: tx.coins ?? 0,
    source: tx.source ?? null,
    meta: tx.meta ?? {},
    country_code: country,
  }
  const { error } = await supabase.from('transactions').insert(payload)
  return error ? { ok: false, error: error.message } : { ok: true }
}

export type NewWithdrawal = {
  beneficiary_type: 'artist' | 'dj'
  beneficiary_id: string
  amount_mwk: number
  method: string
  note?: string | null
  meta?: Record<string, any>
}

export async function requestWithdrawal(w: NewWithdrawal): Promise<{ ok: boolean; error?: string }> {
  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return { ok: false, error: 'service-role missing' }
  const country = await getAdminCountryCode()
  const payload = {
    beneficiary_type: w.beneficiary_type,
    beneficiary_id: w.beneficiary_id,
    amount_mwk: w.amount_mwk,
    method: w.method,
    note: w.note ?? null,
    meta: w.meta ?? {},
    country_code: country,
  }
  const { error } = await supabase.from('withdrawals').insert(payload)
  return error ? { ok: false, error: error.message } : { ok: true }
}
