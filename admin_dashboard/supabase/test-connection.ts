import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'

// Load .env.local
dotenv.config({ path: '.env.local' })

function normalizeEnv(name: string): string {
  const raw = process.env[name]
  if (!raw) {
    throw new Error(
      `Missing ${name}. Create .env.local and set ${name} (no quotes).`,
    )
  }
  const trimmed = raw.trim().replace(/^['"]|['"]$/g, '')
  if (trimmed !== raw) {
    console.warn(`Warning: ${name} had leading/trailing whitespace or quotes; using trimmed value.`)
  }
  if (trimmed.includes('...')) {
    throw new Error(
      `${name} looks truncated (contains "..."). Paste the full key from Supabase Settings → API (single line).`,
    )
  }
  if (/\bdropped\b/i.test(trimmed)) {
    throw new Error(
      `${name} contains the word "Dropped" which usually means extra text got appended during copy/paste. Remove it and paste the exact key.`,
    )
  }
  if (trimmed.includes('<') || trimmed.toLowerCase().includes('paste_')) {
    throw new Error(`Placeholder detected in ${name}. Paste the real value from Supabase Settings → API.`)
  }
  return trimmed
}

function looksLikeJwt(value: string): boolean {
  return value.split('.').length === 3
}

function looksLikeSupabasePublishableKey(value: string): boolean {
  return value.startsWith('sb_publishable_')
}

const supabaseUrl = normalizeEnv('NEXT_PUBLIC_SUPABASE_URL')
const supabaseAnonKey = normalizeEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY')

if (!(looksLikeJwt(supabaseAnonKey) || looksLikeSupabasePublishableKey(supabaseAnonKey))) {
  const parts = supabaseAnonKey.split('.')
  console.error(
    `NEXT_PUBLIC_SUPABASE_ANON_KEY metadata: length=${supabaseAnonKey.length}, dotCount=${parts.length - 1}`,
  )
  throw new Error(
    `NEXT_PUBLIC_SUPABASE_ANON_KEY must be either a JWT (3 parts) or a Supabase publishable key (sb_publishable_...). Re-copy the Publishable or Anon key from Supabase Settings → API.`,
  )
}

const supabase = createClient(supabaseUrl, supabaseAnonKey)

async function test() {
  // Auth endpoint is a safer connectivity check than `/rest/v1/` which can return
  // misleading responses for publishable/anon keys.
  const authSettingsUrl = `${supabaseUrl.replace(/\/$/, '')}/auth/v1/settings`
  const authRes = await fetch(authSettingsUrl, {
    method: 'GET',
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${supabaseAnonKey}`,
      Accept: 'application/json',
    },
  })

  if (authRes.status === 401) {
    const body = await authRes.text()
    throw new Error(`Supabase Auth rejected the key (401). Response: ${body}`)
  }

  console.log(`Auth endpoint reachable (status ${authRes.status}).`)

  // Optional DB check: this may fail if the table doesn't exist or RLS blocks it.
  // Only treat it as fatal when it clearly indicates an invalid API key.
  const { data, error } = await supabase.from('users').select('*').limit(1)
  if (error) {
    const message = error.message ?? ''
    if (typeof message === 'string' && message.toLowerCase().includes('invalid api key')) {
      throw new Error(`Invalid API key (from PostgREST). Details: ${message}`)
    }
    console.error('Query Error (this may be OK):', error)
    return
  }
  console.log('Sample users row(s):', data)
}

test()

