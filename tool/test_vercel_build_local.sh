#!/usr/bin/env bash
set -euo pipefail

# Local end-to-end test that mimics Vercel:
# - Assumes `assets/config/supabase.env.json` is NOT committed
# - Uses WEAFRICA_ENV_JSON_BASE64 (generated locally) to create the asset at build time
# - Runs the same build script used by Vercel
# - Verifies key output files exist
#
# Run:
#   bash tool/test_vercel_build_local.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ASSET_ENV_JSON="assets/config/supabase.env.json"
TOOL_ENV_JSON="tool/supabase.env.json"
BASE64_FILE="tool/WEAFRICA_ENV_JSON_BASE64.txt"

ASSET_BAK="${ASSET_ENV_JSON}.bak_vercel_test"
TOOL_BAK="${TOOL_ENV_JSON}.bak_vercel_test"

restore_env_files() {
  if [[ -f "$ASSET_BAK" ]]; then
    mv -f "$ASSET_BAK" "$ASSET_ENV_JSON"
  fi
  if [[ -f "$TOOL_BAK" ]]; then
    mv -f "$TOOL_BAK" "$TOOL_ENV_JSON"
  fi
}
trap restore_env_files EXIT

if [[ ! -f "$BASE64_FILE" ]]; then
  echo "Missing $BASE64_FILE" >&2
  echo "Run: bash tool/generate_vercel_env_base64.sh" >&2
  exit 1
fi

# Simulate Vercel: env json files not present in repo
if [[ -f "$ASSET_ENV_JSON" ]]; then
  mv "$ASSET_ENV_JSON" "$ASSET_BAK"
fi
if [[ -f "$TOOL_ENV_JSON" ]]; then
  mv "$TOOL_ENV_JSON" "$TOOL_BAK"
fi

export WEAFRICA_ENV_JSON_BASE64
WEAFRICA_ENV_JSON_BASE64="$(<"$BASE64_FILE")"

bash tool/build_web_vercel.sh

# Output sanity checks (no secrets)
[[ -f build/web/index.html ]]
[[ -f build/web/firebase-messaging-sw.js ]]
grep -q "musicweb.weafrica.net" build/web/index.html

echo "✅ local-vercel-build-ok"