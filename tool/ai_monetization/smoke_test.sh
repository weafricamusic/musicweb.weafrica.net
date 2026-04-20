#!/usr/bin/env bash
set -euo pipefail

# Step 13 — AI Monetization Engine smoke test
# Usage:
#   BASE_URL="https://<ref>.functions.supabase.co" \
#   ID_TOKEN="<firebase id token>" \
#   TEST_TOKEN="<optional x-weafrica-test-token>" \
#   ./tool/ai_monetization/smoke_test.sh

BASE_URL="${BASE_URL:-}"
ID_TOKEN="${ID_TOKEN:-}"
TEST_TOKEN="${TEST_TOKEN:-}"
DIAG_TOKEN="${DIAG_TOKEN:-}"
WEAFRICA_DEBUG_DIAG_TOKEN="${WEAFRICA_DEBUG_DIAG_TOKEN:-}"
WEAFRICA_DIAG_TOKEN="${WEAFRICA_DIAG_TOKEN:-}"
DIAG_HEADER="${DIAG_HEADER:-}"

if [[ -z "$BASE_URL" ]]; then
  echo "BASE_URL is required (e.g. https://<ref>.functions.supabase.co)" >&2
  exit 2
fi

api() {
  local method="$1"; shift
  local path="$1"; shift
  local body="${1:-}"

  local printer=("cat")
  if command -v python3 >/dev/null 2>&1; then
    printer=("python3" "-m" "json.tool")
  fi

  local headers=("-H" "Accept: application/json")
  if [[ -n "$ID_TOKEN" ]]; then
    headers+=("-H" "Authorization: Bearer $ID_TOKEN")
  fi
  if [[ -n "$TEST_TOKEN" ]]; then
    headers+=("-H" "x-weafrica-test-token: $TEST_TOKEN")
  fi

  if [[ "$method" == "GET" ]]; then
    curl -sS -X GET "${BASE_URL}${path}" "${headers[@]}" | "${printer[@]}"
  else
    curl -sS -X "$method" "${BASE_URL}${path}" "${headers[@]}" \
      -H "Content-Type: application/json" \
      --data "$body" | "${printer[@]}"
  fi
}

json_get() {
  local key="$1"; shift
  local raw="$1"; shift

  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import json,sys
key=sys.argv[1]
raw=sys.argv[2]
try:
  d=json.loads(raw)
except Exception:
  print("")
  sys.exit(0)

def get_path(obj, path):
  cur=obj
  for p in path.split('.'):
    if not isinstance(cur, dict):
      return None
    cur=cur.get(p)
  return cur

v=get_path(d, key)
if v is None:
  print("")
elif isinstance(v, (str,int,float,bool)):
  print(str(v))
else:
  print(json.dumps(v))
PY
  else
    # best-effort fallback (handles only shallow keys)
    echo "$raw" | sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"?([^\",}]*)\"?.*/\1/p" | head -n 1
  fi
}

echo "\n== Diag (safe; confirms secrets present) =="

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

diag_resp="$(curl -sS -X GET "${BASE_URL}/api/diag" "${diag_headers[@]}" -w "\n%{http_code}")"
diag_code="$(echo "$diag_resp" | tail -n 1)"
diag_raw="$(echo "$diag_resp" | sed '$d')"

if [[ "$diag_code" != "200" ]]; then
  if [[ "$diag_code" == "404" ]]; then
    echo "(diag disabled) Set Edge Function secret WEAFRICA_DEBUG_DIAG_TOKEN and rerun with DIAG_TOKEN or WEAFRICA_DEBUG_DIAG_TOKEN." >&2
    diag_ok=1
  elif [[ "$diag_code" == "403" ]]; then
    echo "(diag forbidden) Invalid/missing diag token header. Provide DIAG_TOKEN (preferred) or WEAFRICA_DIAG_TOKEN (legacy)." >&2
    echo "$diag_raw" >&2
    exit 1
  else
    echo "(diag failed) HTTP $diag_code" >&2
    echo "$diag_raw" >&2
    exit 1
  fi
else
  echo "$diag_raw" | (command -v python3 >/dev/null 2>&1 && python3 -m json.tool || cat)

  diag_ok=1
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json,sys
d=json.load(sys.stdin)
env=d.get("env") or {}
ok=bool(d.get("ok"))
has_project=bool(env.get("has_firebase_project_id"))
has_role=bool(env.get("has_supabase_service_role_key") or env.get("has_service_role_key"))
sys.exit(0 if (ok and has_project and has_role) else 1)
' <<<"$diag_raw" >/dev/null 2>&1; then
      diag_ok=0
    fi
  else
    echo "$diag_raw" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' || diag_ok=0
    echo "$diag_raw" | grep -q '"has_firebase_project_id"[[:space:]]*:[[:space:]]*true' || diag_ok=0
    (echo "$diag_raw" | grep -q '\"has_supabase_service_role_key\"[[:space:]]*:[[:space:]]*true' || \
     echo "$diag_raw" | grep -q '\"has_service_role_key\"[[:space:]]*:[[:space:]]*true') || diag_ok=0
  fi

  if [[ "$diag_ok" != "1" ]]; then
    echo "\nERROR: /api/diag indicates missing required secrets (FIREBASE_PROJECT_ID and/or SUPABASE_SERVICE_ROLE_KEY)." >&2
    echo "Fix the Edge Function secrets and redeploy, then rerun this smoke test." >&2
    exit 1
  fi
fi

echo "\n== AI pricing (public) =="
api GET "/api/ai/pricing"

echo "\n== AI balance (auth) =="
if [[ -z "$ID_TOKEN" ]]; then
  echo "Skipping: set ID_TOKEN to test /api/ai/balance" >&2
else
  api GET "/api/ai/balance"
fi

echo "\n== Creator AI Dashboard (auth) =="
if [[ -z "$ID_TOKEN" ]]; then
  echo "Skipping: set ID_TOKEN to test /api/dashboard/dj and /api/dashboard/artist" >&2
else
  api GET "/api/dashboard/dj?window_days=7"
  api GET "/api/dashboard/artist?window_days=7"
fi

echo "\n== Beat generate (monetized) =="
if [[ -z "$ID_TOKEN" && -z "$TEST_TOKEN" ]]; then
  echo "Skipping: set ID_TOKEN (preferred) or TEST_TOKEN (dev-only) to test /api/beat/generate" >&2
else
  # For dev, you can run with TEST_TOKEN if your function has WEAFRICA_ENABLE_TEST_ROUTES=true.
  api POST "/api/beat/generate" '{"style":"afrobeats","bpm":120,"mood":"hype","duration":15}'

  # Run it a few times to verify free limit then 402 payment_required.
  echo "\n== Beat generate x4 (expect free-limit hit) =="
  for i in 1 2 3 4; do
    echo "-- Attempt $i --"
    set +e

    if command -v python3 >/dev/null 2>&1; then
      curl -sS -X POST "${BASE_URL}/api/beat/generate" \
        -H "Accept: application/json" \
        ${ID_TOKEN:+-H "Authorization: Bearer $ID_TOKEN"} \
        ${TEST_TOKEN:+-H "x-weafrica-test-token: $TEST_TOKEN"} \
        -H "Content-Type: application/json" \
        --data '{"style":"afrobeats","bpm":120,"mood":"hype","duration":10}' \
        | python3 -m json.tool
    else
      curl -sS -X POST "${BASE_URL}/api/beat/generate" \
        -H "Accept: application/json" \
        ${ID_TOKEN:+-H "Authorization: Bearer $ID_TOKEN"} \
        ${TEST_TOKEN:+-H "x-weafrica-test-token: $TEST_TOKEN"} \
        -H "Content-Type: application/json" \
        --data '{"style":"afrobeats","bpm":120,"mood":"hype","duration":10}'
    fi

    echo
    set -e
  done
fi

echo "\n== Beat MP3 generation job (auth + Replicate) =="
if [[ -z "$ID_TOKEN" ]]; then
  echo "Skipping: set ID_TOKEN to test /api/beat/audio/start + /api/beat/audio/status" >&2
else
  set +e
  start_raw="$(curl -sS -X POST "${BASE_URL}/api/beat/audio/start" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $ID_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{"style":"afrobeats","bpm":120,"mood":"hype","duration":12}')"
  start_code=$?
  set -e

  if [[ "$start_code" != "0" ]]; then
    echo "Start request failed (network/curl error)." >&2
  else
    echo "$start_raw" | (command -v python3 >/dev/null 2>&1 && python3 -m json.tool || cat)

    job_id="$(json_get "job_id" "$start_raw")"
    if [[ -z "$job_id" ]]; then
      echo "No job_id returned; skipping polling." >&2
    else
      echo "\nPolling job_id=$job_id ..."
      deadline=$(( $(date +%s) + 240 ))

      while true; do
        now=$(date +%s)
        if (( now > deadline )); then
          echo "Timed out waiting for beat MP3 job." >&2
          break
        fi

        status_raw="$(curl -sS -X GET "${BASE_URL}/api/beat/audio/status?job_id=${job_id}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer $ID_TOKEN")"
        echo "$status_raw" | (command -v python3 >/dev/null 2>&1 && python3 -m json.tool || cat)

        st="$(json_get "job.status" "$status_raw")"
        audio_url="$(json_get "job.audio_url" "$status_raw")"
        if [[ "$st" == "succeeded" ]]; then
          echo "\nBeat MP3 succeeded. audio_url=${audio_url:-<none>}"
          break
        fi
        if [[ "$st" == "failed" ]]; then
          echo "\nBeat MP3 failed."
          break
        fi

        sleep 5
      done
    fi
  fi
fi

echo "\n== DJ next (crowd boost messaging) =="
if [[ -z "$ID_TOKEN" && -z "$TEST_TOKEN" ]]; then
  echo "Skipping: set ID_TOKEN or TEST_TOKEN to test /api/dj/next" >&2
else
  api POST "/api/dj/next" '{
    "battle_type": "1v1",
    "style": "battle",
    "current_song_id": "s1",
    "current_song_bpm": 124,
    "likes_per_min": 15,
    "coins_per_min": 50,
    "viewers_change": 3,
    "battle_time_remaining": 35,
    "song_pool": [
      {"id":"s1","bpm":124,"energy":0.7,"genre":"afrobeats"},
      {"id":"s2","bpm":128,"energy":0.9,"genre":"dancehall"},
      {"id":"s3","bpm":112,"energy":0.6,"genre":"amapiano"}
    ]
  }'
fi

echo "\nDone.\n"
