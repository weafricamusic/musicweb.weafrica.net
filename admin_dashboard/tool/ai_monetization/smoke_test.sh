#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-}"
ID_TOKEN="${ID_TOKEN:-}"
TEST_TOKEN="${TEST_TOKEN:-}"
DIAG_TOKEN="${DIAG_TOKEN:-${WEAFRICA_DEBUG_DIAG_TOKEN:-}}"

if [[ -z "$BASE_URL" ]]; then
  echo "Missing BASE_URL. Example:" >&2
  echo "  BASE_URL=\"https://<ref>.functions.supabase.co\" ID_TOKEN=\"<firebase_id_token>\" bash $0" >&2
  exit 2
fi

# Trim trailing slash.
BASE_URL="${BASE_URL%/}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

request() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"

  if [[ "$method" == "GET" ]]; then
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X GET "${BASE_URL}${path}"
  else
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X "$method" "${BASE_URL}${path}" \
      -H 'content-type: application/json' \
      --data "$data"
  fi
}

request_diag() {
  if [[ -n "$DIAG_TOKEN" ]]; then
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X GET "${BASE_URL}/api/diag" \
      -H "x-debug-token: ${DIAG_TOKEN}"
  else
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X GET "${BASE_URL}/api/diag"
  fi
}

request_bearer() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"

  if [[ -z "$ID_TOKEN" ]]; then
    fail "Missing ID_TOKEN for ${path}"
  fi

  if [[ "$method" == "GET" ]]; then
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X GET "${BASE_URL}${path}" -H "authorization: Bearer ${ID_TOKEN}"
  else
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X "$method" "${BASE_URL}${path}" \
      -H 'content-type: application/json' \
      -H "authorization: Bearer ${ID_TOKEN}" \
      --data "$data"
  fi
}

request_dev_or_bearer() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"

  # Production: real Firebase Bearer token.
  if [[ -n "$ID_TOKEN" ]]; then
    request_bearer "$method" "$path" "$data"
    return
  fi

  # Dev-only fallback: x-weafrica-test-token (requires WEAFRICA_ENABLE_TEST_ROUTES=true in Function secrets).
  if [[ -z "$TEST_TOKEN" ]]; then
    fail "Missing ID_TOKEN (required in production) or TEST_TOKEN (dev-only) for ${path}"
  fi

  if [[ "$method" == "GET" ]]; then
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X GET "${BASE_URL}${path}" -H "x-weafrica-test-token: ${TEST_TOKEN}"
  else
    curl -sS -D - -o /tmp/weafrica_smoke_body.json -X "$method" "${BASE_URL}${path}" \
      -H 'content-type: application/json' \
      -H "x-weafrica-test-token: ${TEST_TOKEN}" \
      --data "$data"
  fi
}

status_from_headers() {
  # First HTTP status in the header dump.
  awk 'NR==1{print $2}'
}

echo "BASE_URL=${BASE_URL}"

echo "== GET /api/diag (secrets sanity)"
headers="$(request_diag | cat)"
status="$(printf "%s" "$headers" | status_from_headers)"
[[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
cat /tmp/weafrica_smoke_body.json

diag_raw="$(cat /tmp/weafrica_smoke_body.json)"

diag_has_true() {
  local key="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); env=d.get("env") or {}; sys.exit(0 if env.get(sys.argv[1]) is True else 1)' "$key" <<<"$diag_raw"
    return $?
  fi

  # Grep fallback (best-effort).
  grep -q "\"${key}\":true" /tmp/weafrica_smoke_body.json
}

# Fail fast if the deployed function is missing required secrets.
if ! diag_has_true "has_firebase_project_id"; then
  fail "Missing FIREBASE_PROJECT_ID in deployed function secrets (see /api/diag)."
fi
if ! diag_has_true "has_supabase_service_role_key" && ! diag_has_true "has_service_role_key"; then
  fail "Missing SUPABASE_SERVICE_ROLE_KEY in deployed function secrets (see /api/diag)."
fi

echo "== GET /api/ai/pricing (public)"
headers="$(request GET /api/ai/pricing | cat)"
status="$(printf "%s" "$headers" | status_from_headers)"
[[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
cat /tmp/weafrica_smoke_body.json

echo ""
echo "== POST /api/dj/next (crowd boost detection)"
headers="$(request POST /api/dj/next '{"coins_per_min":9999}' | cat)"
status="$(printf "%s" "$headers" | status_from_headers)"
[[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
cat /tmp/weafrica_smoke_body.json

if [[ -z "$ID_TOKEN" ]]; then
  echo ""
  echo "== GET /api/ai/balance (requires ID_TOKEN)"
  echo "SKIP: set ID_TOKEN to run authenticated checks."
else
  echo ""
  echo "== GET /api/ai/balance (auth)"
  headers="$(request_bearer GET /api/ai/balance | cat)"
  status="$(printf "%s" "$headers" | status_from_headers)"
  [[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
  cat /tmp/weafrica_smoke_body.json
fi

if [[ -z "$ID_TOKEN" && -z "$TEST_TOKEN" ]]; then
  echo ""
  echo "== POST /api/beat/generate (requires ID_TOKEN by default; TEST_TOKEN is dev-only)"
  echo "SKIP: set ID_TOKEN or TEST_TOKEN to run /api/beat/generate checks."
  echo "Note: running this consumes daily free quota for that uid."
  exit 0
fi

echo ""
echo "== POST /api/beat/generate (free until daily limit, then 402)"
# Default server limit is 3; we try 4 times to ensure the final request hits 402.
# WARNING: this will consume the daily free quota for the authenticated user.
for i in 1 2 3 4; do
  headers="$(request_dev_or_bearer POST /api/beat/generate '{"prompt":"smoke test"}' | cat)"
  status="$(printf "%s" "$headers" | status_from_headers)"
  echo "Attempt ${i}: HTTP ${status}"
  cat /tmp/weafrica_smoke_body.json
  if [[ "$i" -lt 4 ]]; then
    [[ "$status" == "200" ]] || fail "Expected 200 on attempt ${i}, got ${status}"
  else
    [[ "$status" == "402" ]] || fail "Expected 402 on attempt ${i}, got ${status}"
  fi
  echo ""
done

echo "OK"
