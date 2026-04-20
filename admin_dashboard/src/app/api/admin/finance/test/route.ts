import { NextResponse } from 'next/server'
import { getAdminCountryCode } from '@/lib/country/context'
import { getAdminContext, assertPermission } from '@/lib/admin/session'
import { tryCreateSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

export async function GET() {
	if (process.env.NODE_ENV === 'production') {
		return NextResponse.json({ error: 'Not found' }, { status: 404 })
	}

  const adminCtx = await getAdminContext()
  if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  try { assertPermission(adminCtx, 'can_manage_finance') } catch { return NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }

  try {
    const supabase = tryCreateSupabaseAdminClient()
    if (!supabase) {
      return NextResponse.json(
        { error: 'SUPABASE_SERVICE_ROLE_KEY is required for this admin test endpoint (no anon fallback).' },
        { status: 500 },
      )
    }
    const code = await getAdminCountryCode()
    const { data: summary, error: err1 } = await supabase.rpc('finance_top_summary', { p_country_code: code })
    const { data: artistOverview, error: err2 } = await supabase.rpc('finance_earnings_overview', {
      p_beneficiary_type: 'artist',
      p_country_code: code,
    })
    return NextResponse.json({ code, summary, artistOverview, errors: [err1?.message, err2?.message].filter(Boolean) })
  } catch {
    return NextResponse.json({ error: 'failed' }, { status: 500 })
  }
}
