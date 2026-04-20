#!/usr/bin/env bash
set -euo pipefail

# Live Battle smoke test (backend)
#
# Requires TWO Firebase ID tokens (two users):
#   BASE_URL="https://<ref>.functions.supabase.co" \
#   ID_TOKEN_A="<token for DJ A>" \
#   ID_TOKEN_B="<token for DJ B>" \
#   ROLE="dj" \
#   ./tool/live_battle/smoke_test.sh
#
# Notes:
# - Uses quick match to create a battle.
# - Verifies ready/start/status/end.
# - Optionally tries /api/agora/token for each host (requires Agora env configured).

BASE_URL="${BASE_URL:-}"
ID_TOKEN_A="${ID_TOKEN_A:-}"
ID_TOKEN_B="${ID_TOKEN_B:-}"
ROLE="${ROLE:-dj}" # dj | artist
DURATION_SECONDS="${DURATION_SECONDS:-120}"
DIAG_TOKEN="${DIAG_TOKEN:-}"
WEAFRICA_DEBUG_DIAG_TOKEN="${WEAFRICA_DEBUG_DIAG_TOKEN:-}"
WEAFRICA_DIAG_TOKEN="${WEAFRICA_DIAG_TOKEN:-}"
DIAG_HEADER="${DIAG_HEADER:-}"

if [[ -z "$BASE_URL" ]]; then
  echo "BASE_URL is required (e.g. https://<ref>.functions.supabase.co)" >&2
  exit 2
fi
if [[ -z "$ID_TOKEN_A" || -z "$ID_TOKEN_B" ]]; then
  echo "ID_TOKEN_A and ID_TOKEN_B are required" >&2
  exit 2
fi

api() {
  local path="$1"
  echo "${BASE_URL%/}${path}"
}

py_get() {
  local key="$1"
  python3 - "$key" <<'PY'
import json, sys
key = sys.argv[1]
raw = sys.stdin.read().strip()
try:
  j = json.loads(raw) if raw else {}
except Exception:
  j = {}
cur = j
for part in key.split('.'):
  if isinstance(cur, dict) and part in cur:
    cur = cur[part]
  else:
    cur = None
    break
if cur is None:
  sys.exit(1)
if isinstance(cur, (dict, list)):
  print(json.dumps(cur))
else:
  print(cur)
PY
}

curl_json() {
  local method="$1"
  local url="$2"
  local bearer="$3"
  local body="${4:-}"

  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $bearer" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json; charset=utf-8" \
      --data "$body" \
      -w "\n%{http_code}"
  else
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $bearer" \
      -H "Accept: application/json" \
      -w "\n%{http_code}"
  fi
}

expect_200_ok() {
  local name="$1"
  local resp="$2"

  local code body
  code="$(echo "$resp" | tail -n 1)"
  body="$(echo "$resp" | sed '$d')"

  if [[ "$code" != "200" ]]; then
    echo "[$name] HTTP $code" >&2
    echo "$body" >&2
    exit 1
  fi

  echo "$body" | python3 - <<'PY'
import json, sys
raw = sys.stdin.read().strip()
try:
  j = json.loads(raw) if raw else {}
except Exception:
  print(raw)
  sys.exit(2)
if j.get('ok') is not True:
  print(json.dumps(j, indent=2))
  sys.exit(3)
PY

  echo "$body"
}

echo "== Live Battle smoke test =="
echo "Base URL: $BASE_URL"
echo "Role: $ROLE"

echo "\n[0/7] Diag (optional; helps spot Firebase project mismatch)"
diag_token_resolved=""
diag_header_resolved=""
if [[ -n "$DIAG_TOKEN" ]]; then
  diag_token_resolved="$DIAG_TOKEN"
  diag_header_resolved="${DIAG_HEADER:-x-debug-token}"
elif [[ -n "$WEAFRICA_DEBUG_DIAG_TOKEN" ]]; then
  diag_token_resolved="$WEAFRICA_DEBUG_DIAG_TOKEN"
  diag_header_resolved="${DIAG_HEADER:-x-debug-token}"
elif [[ -n "$WEAFRICA_DIAG_TOKEN" ]]; then
  diag_token_resolved="$WEAFRICA_DIAG_TOKEN"
  diag_header_resolved="${DIAG_HEADER:-x-weafrica-diag-token}"
fi

diag_headers=("-H" "Accept: application/json")
if [[ -n "$diag_token_resolved" && -n "$diag_header_resolved" ]]; then
  diag_headers+=("-H" "${diag_header_resolved}: ${diag_token_resolved}")
fi

set +e
diag_resp="$(curl -sS -X GET "${BASE_URL}/api/diag" "${diag_headers[@]}" -w "\n%{http_code}")"
diag_code="$(echo "$diag_resp" | tail -n 1)"
diag_raw="$(echo "$diag_resp" | sed '$d')"
set -e

if [[ "$diag_code" == "200" ]]; then
  echo "$diag_raw" | (command -v python3 >/dev/null 2>&1 && python3 -m json.tool || cat)
elif [[ "$diag_code" == "404" ]]; then
  echo "(diag disabled) set WEAFRICA_DEBUG_DIAG_TOKEN secret and pass DIAG_TOKEN to enable." >&2
elif [[ "$diag_code" == "403" ]]; then
  echo "(diag forbidden) invalid/missing diag token header." >&2
else
  echo "(diag skipped) HTTP $diag_code" >&2
fi

echo "\n[1/7] Quick match join (A)"
resp_a="$(curl_json POST "$(api /api/battle/quick_match/join)" "$ID_TOKEN_A" "{\"role\":\"$ROLE\"}")"
body_a="$(echo "$resp_a" | sed '$d')"
code_a="$(echo "$resp_a" | tail -n 1)"
if [[ "$code_a" != "200" ]]; then
  echo "[join A] HTTP $code_a" >&2
  echo "$body_a" >&2
  exit 1
fi

echo "\n[2/7] Quick match join (B)"
resp_b="$(curl_json POST "$(api /api/battle/quick_match/join)" "$ID_TOKEN_B" "{\"role\":\"$ROLE\"}")"
body_b="$(echo "$resp_b" | sed '$d')"
code_b="$(echo "$resp_b" | tail -n 1)"
if [[ "$code_b" != "200" ]]; then
  echo "[join B] HTTP $code_b" >&2
  echo "$body_b" >&2
  exit 1
fi

battle_json=""
if echo "$body_a" | python3 -c 'import json,sys; j=json.load(sys.stdin); sys.exit(0 if j.get("battle") else 1)' >/dev/null 2>&1; then
  battle_json="$(echo "$body_a" | py_get battle)"
fi
if [[ -z "$battle_json" ]]; then
  if echo "$body_b" | python3 -c 'import json,sys; j=json.load(sys.stdin); sys.exit(0 if j.get("battle") else 1)' >/dev/null 2>&1; then
    battle_json="$(echo "$body_b" | py_get battle)"
  fi
fi

if [[ -z "$battle_json" ]]; then
  echo "\n[3/7] Polling for match (up to ~20s)"
  for _ in {1..10}; do
    sleep 2
    poll_a="$(curl_json GET "$(api /api/battle/quick_match/poll)" "$ID_TOKEN_A")"
    poll_b="$(curl_json GET "$(api /api/battle/quick_match/poll)" "$ID_TOKEN_B")"

    body_pa="$(echo "$poll_a" | sed '$d')"
    body_pb="$(echo "$poll_b" | sed '$d')"

    if echo "$body_pa" | python3 -c 'import json,sys; j=json.load(sys.stdin); sys.exit(0 if j.get("battle") else 1)' >/dev/null 2>&1; then
      battle_json="$(echo "$body_pa" | py_get battle)"
      break
    fi
    if echo "$body_pb" | python3 -c 'import json,sys; j=json.load(sys.stdin); sys.exit(0 if j.get("battle") else 1)' >/dev/null 2>&1; then
      battle_json="$(echo "$body_pb" | py_get battle)"
      break
    fi
  done
fi

if [[ -z "$battle_json" ]]; then
  echo "No match found. Ensure both tokens are valid, and that migrations for matching/invites are applied." >&2
  exit 1
fi

battle_id="$(echo "$battle_json" | py_get battle_id)"
channel_id="$(echo "$battle_json" | py_get channel_id)"

echo "\nMatched battle:"
echo "- battle_id:  $battle_id"
echo "- channel_id: $channel_id"

echo "\n[4/7] Set ready (A)"
ready_a_body="$(expect_200_ok "ready A" "$(curl_json POST "$(api /api/battle/ready)" "$ID_TOKEN_A" "{\"battle_id\":\"$battle_id\",\"ready\":true}")")"

echo "\n[5/7] Set ready (B)"
ready_b_body="$(expect_200_ok "ready B" "$(curl_json POST "$(api /api/battle/ready)" "$ID_TOKEN_B" "{\"battle_id\":\"$battle_id\",\"ready\":true}")")"

echo "\n[6/7] Start battle (A)"
start_body="$(expect_200_ok "start" "$(curl_json POST "$(api /api/battle/start)" "$ID_TOKEN_A" "{\"battle_id\":\"$battle_id\",\"duration_seconds\":$DURATION_SECONDS}")")"

echo "\nBattle started. Checking status…"
status_resp="$(curl_json GET "$(api "/api/battle/status?battle_id=$battle_id")" "$ID_TOKEN_A")"
status_body="$(expect_200_ok "status" "$status_resp")"
status="$(echo "$status_body" | py_get battle.status || true)"
echo "Status: $status"

echo "\n[Optional] Mint Agora host tokens (may return 501 if not configured)"
for who in A B; do
  token_var="ID_TOKEN_${who}"
  bearer="${!token_var}"
  uid="1111"
  [[ "$who" == "B" ]] && uid="2222"

  resp="$(curl_json POST "$(api /api/agora/token)" "$bearer" "{\"channel_id\":\"$channel_id\",\"role\":\"broadcaster\",\"uid\":$uid,\"ttl_seconds\":900}")"
  code="$(echo "$resp" | tail -n 1)"
  body="$(echo "$resp" | sed '$d')"
  if [[ "$code" == "200" ]]; then
    echo "Agora token ($who): ok"
  else
    msg="$(echo "$body" | python3 -c 'import json,sys; 
import json
raw=sys.stdin.read().strip();
try: j=json.loads(raw) if raw else {}
except: j={}
print(j.get("message") or j.get("error") or raw)'
)"
    echo "Agora token ($who): HTTP $code — $msg"
  fi
done

echo "\n[7/7] End battle (A)"
end_body="$(expect_200_ok "end" "$(curl_json POST "$(api /api/battle/end)" "$ID_TOKEN_A" "{\"battle_id\":\"$battle_id\",\"reason\":\"smoke_test\"}")")"

final_status="$(echo "$end_body" | py_get battle.status || true)"
echo "Final status: $final_status"

echo "\nOK: Live Battle backend flow works for role=$ROLE"
