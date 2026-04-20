#!/usr/bin/env bash
set -euo pipefail

# Prints env-config diagnostics WITHOUT printing secret values.
# Useful before pasting WEAFRICA_ENV_JSON_BASE64 into Vercel.
#
# Usage:
#   bash tool/inspect_env_config.sh
#   ENV_JSON=assets/config/supabase.env.json bash tool/inspect_env_config.sh
#   BASE64_FILE=tool/WEAFRICA_ENV_JSON_BASE64.txt bash tool/inspect_env_config.sh

ENV_JSON=${ENV_JSON:-assets/config/supabase.env.json}
BASE64_FILE=${BASE64_FILE:-}

python3 - <<'PY'
import base64, json, os, sys
from pathlib import Path

env_json_path = os.environ.get('ENV_JSON', 'tool/supabase.env.json')
base64_file = os.environ.get('BASE64_FILE', '').strip()

raw_bytes = None
source = None

if base64_file:
  p = Path(base64_file)
  if not p.exists():
    print(f"ERROR: BASE64_FILE not found: {p}", file=sys.stderr)
    sys.exit(1)
  try:
    raw_bytes = base64.b64decode(p.read_text(encoding='utf-8').strip())
  except Exception as e:
    print(f"ERROR: BASE64_FILE is not valid base64: {e}", file=sys.stderr)
    sys.exit(1)
  source = f"base64:{p}"
else:
  p = Path(env_json_path)
  if not p.exists():
    print(f"ERROR: ENV_JSON not found: {p}", file=sys.stderr)
    sys.exit(1)
  raw_bytes = p.read_bytes()
  source = str(p)

try:
  data = json.loads(raw_bytes.decode('utf-8'))
except Exception as e:
  print(f"ERROR: {source} is not valid JSON: {e}", file=sys.stderr)
  sys.exit(1)

if not isinstance(data, dict):
  print(f"ERROR: {source} must be a JSON object (top-level {{...}}).", file=sys.stderr)
  sys.exit(1)

# Guardrail
if data.get('type') == 'service_account' or 'private_key' in data:
  print("ERROR: Config looks like a Google service-account key (contains private_key).", file=sys.stderr)
  sys.exit(1)

keys = sorted([k for k in data.keys() if isinstance(k, str)])

required_web = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'FIREBASE_WEB_API_KEY',
  'FIREBASE_WEB_PROJECT_ID',
  'FIREBASE_WEB_MESSAGING_SENDER_ID',
  'FIREBASE_WEB_APP_ID',
]

missing = [k for k in required_web if not str(data.get(k, '')).strip()]

forbidden_non_empty = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_JWT_SECRET',
  'WEAFRICA_TEST_TOKEN',
  'WEAFRICA_VERCEL_PROTECTION_BYPASS',
  'AGORA_TOKEN',
]

found_forbidden = []
for k in forbidden_non_empty:
  v = data.get(k)
  if isinstance(v, str) and v.strip():
    found_forbidden.append(k)

print(f"Source: {source}")
print(f"Keys present: {len(keys)}")
print("Required (web+FCM):")
for k in required_web:
  ok = "OK" if k not in missing else "MISSING"
  print(f"- {k}: {ok}")

print("\nAll keys (names only):")
for k in keys:
  print(f"- {k}")

if missing:
  print("\nERROR: Missing required keys for web+FCM.", file=sys.stderr)
  sys.exit(2)

if found_forbidden:
  print(
    "\nERROR: Found forbidden non-empty keys for a public web deploy: " + ", ".join(found_forbidden),
    file=sys.stderr,
  )
  sys.exit(3)

print("\n✅ Looks good for Vercel web build.")
PY
