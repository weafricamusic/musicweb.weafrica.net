#!/usr/bin/env bash
set -euo pipefail

# Generates a single-line base64 value suitable for Vercel env var:
#   WEAFRICA_ENV_JSON_BASE64
#
# It reads a local JSON config file (default: assets/config/supabase.env.json) and writes
# the base64-encoded contents to an output file (default: tool/WEAFRICA_ENV_JSON_BASE64.txt).
#
# Usage:
#   bash tool/generate_vercel_env_base64.sh
#   ENV_JSON=assets/config/supabase.env.json OUT_FILE=tool/WEAFRICA_ENV_JSON_BASE64.txt bash tool/generate_vercel_env_base64.sh

ENV_JSON=${ENV_JSON:-assets/config/supabase.env.json}
OUT_FILE=${OUT_FILE:-tool/WEAFRICA_ENV_JSON_BASE64.txt}

if [[ ! -f "$ENV_JSON" ]]; then
  echo "Missing $ENV_JSON" >&2
  echo "Create it from assets/config/supabase.env.json.example (fill real values)" >&2
  exit 1
fi

python3 - "$ENV_JSON" <<'PY'
import json, sys

path = sys.argv[1]
try:
  with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
except Exception as e:
  print(f"ERROR: {path} is not valid JSON: {e}", file=sys.stderr)
  sys.exit(1)

if not isinstance(data, dict):
  print(f"ERROR: {path} must be a JSON object (top-level {{...}}).", file=sys.stderr)
  sys.exit(1)

# Guardrail: never encode Admin SDK service account keys for client deployment.
if data.get('type') == 'service_account' or 'private_key' in data:
  print(f"ERROR: {path} looks like a Google service-account key (private_key).", file=sys.stderr)
  print("Do NOT put service-account JSON into WEAFRICA_ENV_JSON_BASE64.", file=sys.stderr)
  sys.exit(1)

# Guardrail: never ship server-only secrets in a public web config.
required = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'FIREBASE_WEB_API_KEY',
  'FIREBASE_WEB_PROJECT_ID',
  'FIREBASE_WEB_MESSAGING_SENDER_ID',
  'FIREBASE_WEB_APP_ID',
]

missing = [k for k in required if not str(data.get(k, '')).strip()]
if missing:
  print(f"ERROR: {path} is missing required keys for web: {', '.join(missing)}", file=sys.stderr)
  sys.exit(2)

forbidden_non_empty = [
  # Supabase admin/server keys (NEVER in client)
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_JWT_SECRET',
  # App/internal secrets (keep server-side)
  'WEAFRICA_TEST_TOKEN',
  'WEAFRICA_VERCEL_PROTECTION_BYPASS',
  # Agora tokens should be generated server-side for production
  'AGORA_TOKEN',
]

found = []
for k in forbidden_non_empty:
  v = data.get(k)
  if isinstance(v, str) and v.strip():
    found.append(k)

if found:
  print(
    f"ERROR: {path} contains server-only or secret keys that must NOT be shipped to the web client: {', '.join(found)}",
    file=sys.stderr,
  )
  sys.exit(3)
PY

mkdir -p "$(dirname "$OUT_FILE")"

python3 - "$ENV_JSON" "$OUT_FILE" <<'PY'
import base64, pathlib, sys

src = pathlib.Path(sys.argv[1]).read_bytes()
out = base64.b64encode(src).decode('ascii')
pathlib.Path(sys.argv[2]).write_text(out, encoding='utf-8')
PY

echo "✅ Wrote $OUT_FILE"

if command -v pbcopy >/dev/null 2>&1; then
  echo "Copy to clipboard (macOS): pbcopy < $OUT_FILE"
fi

echo "Then in Vercel → Project → Settings → Environment Variables:"
echo "- Set WEAFRICA_ENV_JSON_BASE64 to the contents of that file"
echo "- Remove/replace any placeholder like 'test'"
