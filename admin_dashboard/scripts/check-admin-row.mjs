import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

dotenv.config({ path: '.env.local', override: true });

const email = process.argv[2] || 'admin@weafrica.test';

const url = String(process.env.NEXT_PUBLIC_SUPABASE_URL || '').trim();
const serviceRoleKey = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();

if (!url || !serviceRoleKey) {
  console.log(
    JSON.stringify(
      {
        ok: false,
        error: 'Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY',
      },
      null,
      2,
    ),
  );
  process.exit(0);
}

const supabase = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

try {
  const { data, error } = await supabase
    .from('admins')
    .select('email,role,status')
    .eq('email', email)
    .maybeSingle();

  if (error) {
    console.log(
      JSON.stringify({ ok: false, error: error.message, code: error.code ?? null }, null, 2),
    );
    process.exit(0);
  }

  console.log(
    JSON.stringify({ ok: true, admin_row_exists: Boolean(data), admin: data ?? null }, null, 2),
  );
} catch (e) {
  console.log(JSON.stringify({ ok: false, error: String(e?.message ?? e) }, null, 2));
}
