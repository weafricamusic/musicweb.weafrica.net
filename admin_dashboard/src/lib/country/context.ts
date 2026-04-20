import 'server-only'
import { cookies } from 'next/headers'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

const ADMIN_COUNTRY_COOKIE = 'admin_country'

export async function getAdminCountryCode(): Promise<string> {
  const store = await cookies()
  const code = store.get(ADMIN_COUNTRY_COOKIE)?.value?.toUpperCase()?.trim()
  return code && code.length === 2 ? code : 'MW'
}

export async function setAdminCountryCookie(code: string) {
  const store = await cookies()
  store.set(ADMIN_COUNTRY_COOKIE, code.toUpperCase(), {
    httpOnly: true,
    sameSite: 'lax',
    secure: true,
    path: '/',
    maxAge: 60 * 60 * 24 * 30, // 30 days
  })
}

export type CountryConfig = {
  country_code: string
  country_name: string
  currency_code: string
  currency_symbol: string
  coin_rate: number
  min_payout_amount: number
  payment_methods: unknown
  live_stream_enabled: boolean
  ads_enabled: boolean
  premium_enabled: boolean
  is_active: boolean
}

export async function getCountryConfigByCode(code: string): Promise<CountryConfig | null> {
  const supabase = tryCreateSupabaseAdminClient()
  if (!supabase) return null

  // Prefer the RPC (new schema), but fall back to direct table reads for legacy schemas.
  try {
    const { data, error } = await supabase.rpc('get_country_config', { p_code: code })
    if (!error && data && Array.isArray(data) && data.length > 0) {
      return data[0] as CountryConfig
    }
  } catch {
    // ignore
  }

  function normalize(v: unknown, fallback: string): string {
    const s = String(v ?? '').trim()
    return s || fallback
  }

  function asBool(v: unknown, fallback: boolean): boolean {
    return typeof v === 'boolean' ? v : fallback
  }

  function asNumber(v: unknown, fallback: number): number {
    return typeof v === 'number' && Number.isFinite(v) ? v : fallback
  }

  // Newer table shape.
  try {
    const { data, error } = await supabase
      .from('countries')
      .select('country_code,country_name,currency_code,currency_symbol,coin_rate,min_payout_amount,payment_methods,live_stream_enabled,ads_enabled,premium_enabled,is_active')
      .eq('country_code', code)
      .limit(1)
      .maybeSingle<Record<string, unknown>>()
    if (!error && data) {
      return {
        country_code: normalize(data.country_code, code),
        country_name: normalize(data.country_name, code),
        currency_code: normalize(data.currency_code, 'USD'),
        currency_symbol: normalize(data.currency_symbol, '$'),
        coin_rate: asNumber(data.coin_rate, 100),
        min_payout_amount: asNumber(data.min_payout_amount, 0),
        payment_methods: (data.payment_methods ?? null) as unknown,
        live_stream_enabled: asBool(data.live_stream_enabled, true),
        ads_enabled: asBool(data.ads_enabled, false),
        premium_enabled: asBool(data.premium_enabled, false),
        is_active: asBool(data.is_active, true),
      }
    }
  } catch {
    // ignore
  }

  // Legacy: `code` + `name`.
  try {
    const { data, error } = await supabase
      .from('countries')
      .select('code,name,currency_code,currency_symbol,coin_rate,min_payout_amount,payment_methods,live_stream_enabled,ads_enabled,premium_enabled,is_active')
      .eq('code', code)
      .limit(1)
      .maybeSingle<Record<string, unknown>>()
    if (!error && data) {
      return {
        country_code: normalize(data.code, code),
        country_name: normalize(data.name, code),
        currency_code: normalize(data.currency_code, 'USD'),
        currency_symbol: normalize(data.currency_symbol, '$'),
        coin_rate: asNumber(data.coin_rate, 100),
        min_payout_amount: asNumber(data.min_payout_amount, 0),
        payment_methods: (data.payment_methods ?? null) as unknown,
        live_stream_enabled: asBool(data.live_stream_enabled, true),
        ads_enabled: asBool(data.ads_enabled, false),
        premium_enabled: asBool(data.premium_enabled, false),
        is_active: asBool(data.is_active, true),
      }
    }
  } catch {
    // ignore
  }

  return null
}

export async function convertUsdToCoins(usd: number, country: CountryConfig | null): Promise<number> {
  const rate = country?.coin_rate ?? 100
  return Math.max(0, Math.round(usd * rate))
}
