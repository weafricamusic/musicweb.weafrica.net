import { NextResponse, type NextRequest } from 'next/server'
import { getCountryConfigByCode, setAdminCountryCookie } from '@/lib/country/context'
import { getAdminContext } from '@/lib/admin/session'

export const runtime = 'nodejs'

export async function POST(req: NextRequest) {
  const adminCtx = await getAdminContext()
  if (!adminCtx) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  try {
    let code: string | undefined
    const ctype = req.headers.get('content-type') || ''
    if (ctype.includes('application/json')) {
      const body = (await req.json()) as { code?: string }
      code = body?.code
    } else {
      const form = await req.formData()
      code = (form.get('code') as string | null) ?? undefined
    }
    const normalized = (code ?? '').trim().toUpperCase()
    if (!/^[A-Z]{2}$/.test(normalized)) {
      return NextResponse.json({ error: 'Invalid code' }, { status: 400 })
    }
    // Validate against active countries if possible (service role)
    const existing = await getCountryConfigByCode(normalized)
    if (!existing || !existing.is_active) {
      return NextResponse.json({ error: 'Unknown or inactive country' }, { status: 400 })
    }
    await setAdminCountryCookie(normalized)
    return NextResponse.json({ ok: true, code: normalized })
  } catch {
    return NextResponse.json({ error: 'Failed to set country' }, { status: 500 })
  }
}
