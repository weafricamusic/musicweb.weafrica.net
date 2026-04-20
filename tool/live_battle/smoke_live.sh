#!/usr/bin/env bash
set -euo pipefail

# Live (non-battle) smoke helper
#
# Usage:
#   BASE_URL="https://<ref>.functions.supabase.co" \
#   ID_TOKEN="<firebase id token>" \
#   DIAG_TOKEN="<optional diag token>" \
#   CHANNEL_ID="weafrica_live_smoke_$(date +%s)" \
#   ./tool/live_battle/smoke_live.sh

BASE_URL="${BASE_URL:-}"
ID_TOKEN="${ID_TOKEN:-}"
CHANNEL_ID="${CHANNEL_ID:-weafrica_live_smoke_$(date +%s)}"
TTL_SECONDS="${TTL_SECONDS:-900}"

DIAG_TOKEN="${DIAG_TOKEN:-}"
WEAFRICA_DEBUG_DIAG_TOKEN="${WEAFRICA_DEBUG_DIAG_TOKEN:-}"
WEAFRICA_DIAG_TOKEN="${WEAFRICA_DIAG_TOKEN:-}"
DIAG_HEADER="${DIAG_HEADER:-}"

if [[ -z "$BASE_URL" ]]; then
  echo "BASE_URL is required (e.g. https://<ref>.functions.supabase.co)" >&2
  exit 2
fi
if [[ -z "$ID_TOKEN" ]]; then
  echo "ID_TOKEN is required (Firebase Auth ID token)" >&2
  exit 2
fi

maybe_diag() {
  local token=""
  local header=""

  if [[ -n "$DIAG_TOKEN" ]]; then
    token="$DIAG_TOKEN"
    header="${DIAG_HEADER:-x-debug-token}"
  elif [[ -n "$WEAFRICA_DEBUG_DIAG_TOKEN" ]]; then
    token="$WEAFRICA_DEBUG_DIAG_TOKEN"
    header="${DIAG_HEADER:-x-debug-token}"
  elif [[ -n "$WEAFRICA_DIAG_TOKEN" ]]; then
    token="$WEAFRICA_DIAG_TOKEN"
    header="${DIAG_HEADER:-x-weafrica-diag-token}"
  fi

  local headers=("-H" "Accept: application/json")
  if [[ -n "$token" && -n "$header" ]]; then
    headers+=("-H" "${header}: ${token}")
  fi

  set +e
  local resp
  resp="$(curl -sS -X GET "${BASE_URL}/api/diag" "${headers[@]}" -w "\n%{http_code}")"
  local code
  code="$(echo "$resp" | tail -n 1)"
  local body
  body="$(echo "$resp" | sed '$d')"
  set -e

  if [[ "$code" == "200" ]]; then
    echo "== /api/diag =="
    echo "$body" | (command -v python3 >/dev/null 2>&1 && python3 -m json.tool || cat)
  elif [[ "$code" == "404" ]]; then
    echo "(diag disabled) set WEAFRICA_DEBUG_DIAG_TOKEN secret to enable /api/diag" >&2
  elif [[ "$code" == "403" ]]; then
    echo "(diag forbidden) invalid/missing diag token header" >&2
  else
    echo "(diag skipped) HTTP $code" >&2
  fi
}

maybe_diag

echo "== Agora token (broadcaster) =="
echo "channel_id=$CHANNEL_ID ttl_seconds=$TTL_SECONDS"

curl -sS -X POST "${BASE_URL}/api/agora/token" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data "{\"channel_id\":\"$CHANNEL_ID\",\"role\":\"broadcaster\",\"ttl_seconds\":$TTL_SECONDS}" \
  | (command -v python3 >/dev/null 2>&1 && python3 -m json.tool || cat)
