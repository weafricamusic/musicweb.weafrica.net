import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'

// Load .env.local
dotenv.config({ path: '.env.local' })

function normalize(name: string, required = true): string | undefined {
  const raw = process.env[name]
  if (!raw) {
    if (required) throw new Error(`Missing ${name}. Set it in .env.local and restart dev server.`)
    return undefined
  }
  const trimmed = raw.trim().replace(/^['"]|['"]$/g, '')
  if (!trimmed) {
    if (required) throw new Error(`Empty ${name}.`)
    return undefined
  }
  // Remove accidental whitespace/newlines from env providers
  const compact = trimmed.replace(/\s+/g, '')
  return compact
}

function looksLikeJwt(value: string): boolean {
  return value.split('.').length === 3
}

async function main() {
  const url = normalize('NEXT_PUBLIC_SUPABASE_URL')!
  const serviceKey = normalize('SUPABASE_SERVICE_ROLE_KEY')!

  if (!looksLikeJwt(serviceKey)) {
    const parts = serviceKey.split('.')
    console.warn(`SUPABASE_SERVICE_ROLE_KEY metadata: length=${serviceKey.length}, dotCount=${parts.length - 1}`)
    console.warn('Note: Service role key should be a JWT-like string (3 parts).')
  }

  const supabase = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })

  // Quick auth reachability probe using REST Auth settings
  const authSettingsUrl = `${url.replace(/\/$/, '')}/auth/v1/settings`
  const authRes = await fetch(authSettingsUrl, {
    method: 'GET',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      Accept: 'application/json',
    },
  })

  if (authRes.status === 401) {
    const body = await authRes.text()
    throw new Error(`Service role rejected (401). Response: ${body}`)
  }
  console.log(`Service role Auth reachable (status ${authRes.status}).`)

  // Optional DB check expected to succeed with service role under RLS
  const { data, error } = await supabase.from('admins').select('id').limit(1)
  if (error) {
    console.error('DB probe error (table may be missing, check migrations):', error)
  } else {
    console.log('DB probe OK (admins rows sample):', data)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
