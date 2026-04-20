#!/usr/bin/env bash
set -euo pipefail

# Build Flutter web for deployment on Vercel.
#
# This script is designed to run in Vercel's build environment (Linux) where
# Flutter is not installed by default. If `flutter` is already available on
# PATH (local dev / CI), it will be used.
#
# Required config:
# - Provide `assets/config/supabase.env.json` in the repo OR set one of:
#     - WEAFRICA_ENV_JSON (raw JSON string)
#     - WEAFRICA_ENV_JSON_BASE64 (base64-encoded JSON)
#   The same JSON is copied to `tool/supabase.env.json` for --dart-define-from-file.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ASSET_ENV_JSON="assets/config/supabase.env.json"
TOOL_ENV_JSON="tool/supabase.env.json"

assert_not_service_account_json() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  if grep -Eq '"private_key"[[:space:]]*:|"type"[[:space:]]*:[[:space:]]*"service_account"|BEGIN PRIVATE KEY' "$path"; then
    echo "ERROR: $path appears to contain a Google service account key (private_key)." >&2
    echo "Do NOT ship service-account JSON to the web client." >&2
    echo "For Flutter web/FCM use Firebase Web config (FIREBASE_WEB_*), not Admin SDK credentials." >&2
    exit 1
  fi
}

assert_no_client_secrets_json() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  python3 - "$path" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
  data = json.load(f)

if not isinstance(data, dict):
  print(f"ERROR: {path} must be a JSON object (top-level {{...}}).", file=sys.stderr)
  sys.exit(1)

if data.get('type') == 'service_account' or 'private_key' in data:
  print(f"ERROR: {path} looks like a Google service-account key (private_key).", file=sys.stderr)
  sys.exit(1)

forbidden_non_empty = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_JWT_SECRET',
  'WEAFRICA_TEST_TOKEN',
  'WEAFRICA_VERCEL_PROTECTION_BYPASS',
  'AGORA_TOKEN',
]

found = []
for k in forbidden_non_empty:
  v = data.get(k)
  if isinstance(v, str) and v.strip():
    found.append(k)

if found:
  print(
    f"ERROR: Refusing to build because {path} contains server-only/secret keys that would be shipped to the web client: {', '.join(found)}",
    file=sys.stderr,
  )
  sys.exit(1)
PY
}

assert_valid_json_object() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  python3 - "$path" <<'PY'
import json, sys

path = sys.argv[1]
try:
  with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
except Exception as e:
  print(f"ERROR: {path} is not valid JSON: {e}", file=sys.stderr)
  print("Hint: WEAFRICA_ENV_JSON must be a JSON object like {\"SUPABASE_URL\":\"...\",\"SUPABASE_ANON_KEY\":\"...\"}.", file=sys.stderr)
  print("Better: set WEAFRICA_ENV_JSON_BASE64 to a base64-encoded JSON file to avoid quoting issues.", file=sys.stderr)
  sys.exit(1)

if not isinstance(data, dict):
  print(f"ERROR: {path} must be a JSON object (top-level {{...}}).", file=sys.stderr)
  sys.exit(1)
PY
}

write_env_json_from_env() {
  mkdir -p "$(dirname "$ASSET_ENV_JSON")" "$(dirname "$TOOL_ENV_JSON")"

  if [[ -n "${WEAFRICA_ENV_JSON_BASE64:-}" ]]; then
    python3 - <<'PY' >"$ASSET_ENV_JSON"
import os, base64, sys

raw = os.environ.get('WEAFRICA_ENV_JSON_BASE64', '')
try:
  decoded = base64.b64decode(raw)
except Exception as e:
  print(f"ERROR: WEAFRICA_ENV_JSON_BASE64 is not valid base64: {e}", file=sys.stderr)
  sys.exit(1)

sys.stdout.buffer.write(decoded)
PY
  elif [[ -n "${WEAFRICA_ENV_JSON:-}" ]]; then
    printf '%s' "$WEAFRICA_ENV_JSON" >"$ASSET_ENV_JSON"
  else
    return 1
  fi

  cp "$ASSET_ENV_JSON" "$TOOL_ENV_JSON"
  return 0
}

if [[ ! -f "$ASSET_ENV_JSON" ]]; then
  if ! write_env_json_from_env; then
    echo "Missing $ASSET_ENV_JSON." >&2
    echo "Provide it in-repo, or set WEAFRICA_ENV_JSON / WEAFRICA_ENV_JSON_BASE64 in Vercel env vars." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$TOOL_ENV_JSON")"
cp "$ASSET_ENV_JSON" "$TOOL_ENV_JSON"

assert_not_service_account_json "$ASSET_ENV_JSON"
assert_valid_json_object "$ASSET_ENV_JSON"
assert_no_client_secrets_json "$ASSET_ENV_JSON"

ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "flutter not found on PATH, and auto-install is only implemented for Linux." >&2
    echo "Install Flutter locally, or run this script in a Linux CI." >&2
    exit 1
  fi

  local cache_dir="${FLUTTER_CACHE_DIR:-.vercel/cache/flutter}"
  local sdk_dir="$cache_dir/flutter"
  local flutter_bin="$sdk_dir/bin/flutter"

  mkdir -p "$cache_dir"

  if [[ ! -x "$flutter_bin" ]]; then
    echo "Downloading Flutter SDK (stable)..." >&2

    local releases_json_url="${FLUTTER_RELEASES_JSON_URL:-https://flutter_infra_release.appspot.com/releases/releases_linux.json}"

    local archive_path
    archive_path="$(python3 - "$releases_json_url" <<'PY'
import json, sys
import urllib.request

url = sys.argv[1]
with urllib.request.urlopen(url) as resp:
  data = json.load(resp)

channel = (data.get('current_release') or {}).get('stable')
if not channel:
  raise SystemExit('Missing current_release.stable in releases json')

for r in data.get('releases', []):
  if r.get('hash') == channel:
    archive = r.get('archive')
    if not archive:
      raise SystemExit('Matched stable hash but missing archive path')
    print(archive)
    raise SystemExit(0)

raise SystemExit('Could not find archive for current stable hash')
PY
)"

    local archive_url="https://flutter_infra_release.appspot.com/releases/$archive_path"

    rm -rf "$sdk_dir"
    curl -fsSL "$archive_url" | tar -xJ --no-same-owner -C "$cache_dir"
  fi

  export PATH="$sdk_dir/bin:$PATH"

  # Vercel's build environment may run as root; the Flutter SDK archive can
  # contain non-root ownership metadata which triggers Git's "dubious ownership"
  # safety checks when Flutter invokes git.
  if command -v git >/dev/null 2>&1; then
    git config --global --add safe.directory "$sdk_dir" >/dev/null 2>&1 || true
  fi

  if ! command -v flutter >/dev/null 2>&1; then
    echo "Flutter install completed, but flutter is still not on PATH." >&2
    exit 1
  fi
}

ensure_flutter

flutter --version
flutter pub get

build_args=(
  build web
  --release
  --base-href /
  --no-wasm-dry-run
  "--dart-define-from-file=$ASSET_ENV_JSON"
)

flutter "${build_args[@]}"

echo "✅ Flutter web build complete: build/web"