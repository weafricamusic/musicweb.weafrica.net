import { NextResponse, type NextRequest } from 'next/server'

import { createSupabaseAdminClient } from '@/lib/supabase/admin'

export const runtime = 'nodejs'

type IngestEvent = {
  event_name: string
  created_at?: string
  user_id?: string | null
  actor_type?: string | null
  actor_id?: string | null
  session_id?: string | null
  country_code?: string | null
  stream_id?: string | null
  platform?: string | null
  app_version?: string | null
  source?: string | null
  properties?: unknown
}

function normalizeEnvOptional(name: string): string | undefined {
  const raw = process.env[name]
  if (!raw) return undefined
  const value = raw.trim().replace(/^['"]|['"]$/g, '')
  return value.length ? value : undefined
}

function badRequest(message: string, extra?: any) {
  return NextResponse.json({ error: message, ...(extra ? { extra } : {}) }, { status: 400 })
}

function unauthorized() {
  return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
}

function tooLarge() {
  return NextResponse.json({ error: 'Too large' }, { status: 413 })
}

function normalizeText(v: unknown, max: number): string | null {
  if (v == null) return null
  const s = String(v).trim()
  if (!s) return null
  return s.length > max ? s.slice(0, max) : s
}

function isIsoDate(s: string): boolean {
  const d = new Date(s)
  return !Number.isNaN(d.getTime())
}

export async function POST(req: NextRequest) {
  const secret = normalizeEnvOptional('EVENTS_INGEST_SECRET')
  if (!secret) {
    return NextResponse.json({ error: 'Server not configured (missing EVENTS_INGEST_SECRET).' }, { status: 503 })
  }

  const header = req.headers.get('x-ingest-secret') || req.headers.get('authorization') || ''
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : header.trim()
  if (token !== secret) return unauthorized()

  const ctype = req.headers.get('content-type') || ''
  if (!ctype.includes('application/json')) {
    return badRequest('Content-Type must be application/json')
  }

  let body: any
  try {
    body = await req.json()
  } catch {
    return badRequest('Invalid JSON')
  }

  const events: IngestEvent[] = Array.isArray(body) ? body : Array.isArray(body?.events) ? body.events : [body]
  if (!events.length) return badRequest('No events')
  if (events.length > 100) return tooLarge()

  const rows = events
    .map((e) => {
      const event_name = normalizeText(e?.event_name, 80)
      if (!event_name) return null

      const created_at_raw = normalizeText(e?.created_at, 40)
      const created_at = created_at_raw && isIsoDate(created_at_raw) ? created_at_raw : null

      return {
        event_name,
        created_at,
        user_id: normalizeText(e?.user_id, 128),
        actor_type: normalizeText(e?.actor_type, 32),
        actor_id: normalizeText(e?.actor_id, 128),
        session_id: normalizeText(e?.session_id, 128),
        country_code: normalizeText(e?.country_code, 8)?.toUpperCase() ?? null,
        stream_id: normalizeText(e?.stream_id, 128),
        platform: normalizeText(e?.platform, 32),
        app_version: normalizeText(e?.app_version, 32),
        source: normalizeText(e?.source, 64),
        properties: e?.properties ?? null,
      }
    })
    .filter(Boolean) as any[]

  if (!rows.length) return badRequest('No valid events')
  if (rows.length > 100) return tooLarge()

  // crude payload guard (prevents accidental huge events)
  try {
    const size = Buffer.byteLength(JSON.stringify(rows), 'utf8')
    if (size > 250_000) return tooLarge()
  } catch {
    // ignore
  }

  try {
    const supabase = createSupabaseAdminClient()
    const { error } = await supabase.from('analytics_events').insert(rows)
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    return NextResponse.json({ ok: true, ingested: rows.length })
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : 'failed' }, { status: 500 })
  }
}
