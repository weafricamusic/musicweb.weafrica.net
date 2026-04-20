#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-}"
ID_TOKEN="${ID_TOKEN:-}"
TEST_TOKEN="${TEST_TOKEN:-}"
DIAG_TOKEN="${DIAG_TOKEN:-${WEAFRICA_DEBUG_DIAG_TOKEN:-}}"
ALLOW_TEST_ROUTES="${ALLOW_TEST_ROUTES:-}"

# Live-specific inputs
CHANNEL_ID="${CHANNEL_ID:-weafrica_live_smoke}"
BATTLE_ID="${BATTLE_ID:-}"

if [[ -z "$BASE_URL" ]]; then
  echo "Missing BASE_URL. Example:" >&2
  echo "  BASE_URL=\"https://<ref>.functions.supabase.co\" bash $0" >&2
  exit 2
fi

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
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X GET "${BASE_URL}${path}"
  else
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X "$method" "${BASE_URL}${path}" \
      -H 'content-type: application/json' \
      --data "$data"
  fi
}

request_diag() {
  if [[ -n "$DIAG_TOKEN" ]]; then
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X GET "${BASE_URL}/api/diag" \
      -H "x-debug-token: ${DIAG_TOKEN}"
  else
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X GET "${BASE_URL}/api/diag"
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
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X GET "${BASE_URL}${path}" \
      -H "authorization: Bearer ${ID_TOKEN}"
  else
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X "$method" "${BASE_URL}${path}" \
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
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X GET "${BASE_URL}${path}" \
      -H "x-weafrica-test-token: ${TEST_TOKEN}"
  else
    curl -sS -D - -o /tmp/weafrica_live_smoke_body.json -X "$method" "${BASE_URL}${path}" \
      -H 'content-type: application/json' \
      -H "x-weafrica-test-token: ${TEST_TOKEN}" \
      --data "$data"
  fi
}

status_from_headers() {
  awk 'NR==1{print $2}'
}

diag_bool() {
  local key="$1"
  local diag_raw="$2"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); env=d.get("env") or {}; print("true" if env.get(sys.argv[1]) is True else "false")' "$key" <<<"$diag_raw"
    return 0
  fi

  if grep -q "\"${key}\":true" /tmp/weafrica_live_smoke_body.json; then
    echo true
  else
    echo false
  fi
}

echo "BASE_URL=${BASE_URL}"

echo "== GET /api/diag (secrets sanity)"
headers="$(request_diag | cat)"
status="$(printf "%s" "$headers" | status_from_headers)"
[[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
cat /tmp/weafrica_live_smoke_body.json

diag_raw="$(cat /tmp/weafrica_live_smoke_body.json)"

# Required for production Live.
for k in has_firebase_project_id has_supabase_service_role_key has_agora_app_id has_agora_app_certificate; do
  v="$(diag_bool "$k" "$diag_raw")"
  if [[ "$v" != "true" ]]; then
    fail "Missing ${k}=true in deployed function secrets (see /api/diag)."
  fi
done

# Must not be enabled in production.
enable_test_routes="$(diag_bool enable_test_routes "$diag_raw")"
if [[ "$enable_test_routes" == "true" && -z "$ALLOW_TEST_ROUTES" ]]; then
  fail "WEAFRICA_ENABLE_TEST_ROUTES appears enabled on the deployed function. Disable it for production (or re-run with ALLOW_TEST_ROUTES=1 for dev)."
fi

echo ""
echo "== POST /api/agora/token (subscriber, public)"
headers="$(request POST /api/agora/token "$(printf '{"channel_id":"%s","role":"subscriber","ttl_seconds":600}' "$CHANNEL_ID")" | cat)"
status="$(printf "%s" "$headers" | status_from_headers)"
[[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
cat /tmp/weafrica_live_smoke_body.json

echo ""
if [[ -n "$ID_TOKEN" || -n "$TEST_TOKEN" ]]; then
  echo "== POST /api/agora/token (publisher, requires auth)"
  headers="$(request_dev_or_bearer POST /api/agora/token "$(printf '{"channel_id":"%s","role":"publisher","ttl_seconds":600}' "$CHANNEL_ID")" | cat)"
  status="$(printf "%s" "$headers" | status_from_headers)"
  [[ "$status" == "200" ]] || fail "Expected 200, got ${status}"
  cat /tmp/weafrica_live_smoke_body.json
else
  echo "== POST /api/agora/token (publisher, requires auth)"
  echo "SKIP: set ID_TOKEN (production) or TEST_TOKEN (dev-only) to verify publisher token issuance."
fi

echo ""
echo "== GET /api/battle/status (public)"
if [[ -z "$BATTLE_ID" ]]; then
  echo "No BATTLE_ID provided; doing a route presence check (expects 400)."
  headers="$(request GET /api/battle/status | cat)"
  status="$(printf "%s" "$headers" | status_from_headers)"
  [[ "$status" == "400" ]] || fail "Expected 400 when battle_id is missing, got ${status}"
  cat /tmp/weafrica_live_smoke_body.json
else
  headers="$(request GET "/api/battle/status?battle_id=${BATTLE_ID}" | cat)"
  status="$(printf "%s" "$headers" | status_from_headers)"
  # 200 (found) or 404 (not found) are both acceptable in smoke.
  if [[ "$status" != "200" && "$status" != "404" ]]; then
    fail "Expected 200 or 404 for battle status, got ${status}"
  fi
  cat /tmp/weafrica_live_smoke_body.json
fi

echo ""
echo "== POST /api/battle/ready (requires auth)"
if [[ -z "$BATTLE_ID" ]]; then
  echo "SKIP: set BATTLE_ID to exercise /api/battle/ready."
elif [[ -z "$ID_TOKEN" && -z "$TEST_TOKEN" ]]; then
  echo "SKIP: set ID_TOKEN (production) or TEST_TOKEN (dev-only) to exercise /api/battle/ready."
else
  headers="$(request_dev_or_bearer POST /api/battle/ready "$(printf '{"battle_id":"%s"}' "$BATTLE_ID")" | cat)"
  status="$(printf "%s" "$headers" | status_from_headers)"
  # 200 (updated), 404 (missing battle), 501 (live_battles not installed) are all useful signals.
  if [[ "$status" != "200" && "$status" != "404" && "$status" != "501" ]]; then
    fail "Expected 200/404/501 for battle ready, got ${status}"
  fi
  cat /tmp/weafrica_live_smoke_body.json
fi

echo "OK"
