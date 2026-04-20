#!/usr/bin/env bash
set -euo pipefail

# Creator role + provisioning smoke test
#
# Verifies that Firebase-authenticated users can be provisioned as Artist and DJ
# using the Edge API endpoints the Flutter app relies on:
#   - GET  /api/auth/role
#   - POST /api/auth/provision-creator
#
# Requirements: curl (and optionally python3 for JSON parsing/pretty printing).
#
# Usage (recommended):
#   BASE_URL="https://<project-ref>.functions.supabase.co" \
#   FIREBASE_WEB_API_KEY="<firebase web api key>" \
#   ARTIST_EMAIL="artist1@weafrica.test" ARTIST_PASSWORD="<pw>" \
#   DJ_EMAIL="dj1@weafrica.test" DJ_PASSWORD="<pw>" \
#   bash tool/creator_role_smoke_test.sh
#
# Alternative (if you already have tokens):
#   BASE_URL="..." ARTIST_ID_TOKEN="..." DJ_ID_TOKEN="..." bash tool/creator_role_smoke_test.sh

BASE_URL="${BASE_URL:-}"
FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY:-${FIREBASE_API_KEY:-}}"
ENV_PATH="${ENV_PATH:-tool/supabase.env.json}"

ARTIST_EMAIL="${ARTIST_EMAIL:-artist1@weafrica.test}"
ARTIST_PASSWORD="${ARTIST_PASSWORD:-}"
ARTIST_DISPLAY_NAME="${ARTIST_DISPLAY_NAME:-artist1}"
ARTIST_ID_TOKEN="${ARTIST_ID_TOKEN:-}"

DJ_EMAIL="${DJ_EMAIL:-dj1@weafrica.test}"
DJ_PASSWORD="${DJ_PASSWORD:-}"
DJ_DISPLAY_NAME="${DJ_DISPLAY_NAME:-dj1}"
DJ_ID_TOKEN="${DJ_ID_TOKEN:-}"

TEST_TOKEN="${TEST_TOKEN:-}"

have_python=0
if command -v python3 >/dev/null 2>&1; then
  have_python=1
fi

looks_placeholder() {
  local v="$1"; shift
  if [[ -z "$v" ]]; then
    return 0
  fi
  # Common placeholder patterns.
  if [[ "$v" == *"<"* || "$v" == *">"* ]]; then
    return 0
  fi
  if [[ "$v" == *"YOUR_"* || "$v" == *"your-"* || "$v" == *"your "* ]]; then
    return 0
  fi
  return 1
}

# If the caller accidentally exported placeholders, ignore them so ENV_PATH can fill real values.
if looks_placeholder "$BASE_URL"; then
  BASE_URL=""
fi
if looks_placeholder "$FIREBASE_WEB_API_KEY"; then
  FIREBASE_WEB_API_KEY=""
fi

load_env_json() {
  if [[ -z "$ENV_PATH" || ! -f "$ENV_PATH" ]]; then
    return 0
  fi

  # Populate BASE_URL and FIREBASE_WEB_API_KEY if missing.
  if [[ "$have_python" == "1" ]]; then
    local loaded
    loaded="$(python3 - "$ENV_PATH" <<'PY' 2>/dev/null
import json,sys
path=sys.argv[1]
try:
  with open(path,'r',encoding='utf-8') as f:
    d=json.load(f)
except Exception:
  sys.exit(0)

def g(k):
  v=d.get(k)
  return (str(v).strip() if v is not None else "")

base=g('WEAFRICA_API_BASE_URL')
api=g('FIREBASE_WEB_API_KEY') or g('FIREBASE_API_KEY')
print(base)
print(api)
PY
)"

    local base_loaded
    base_loaded="$(printf '%s' "$loaded" | sed -n '1p' | tr -d '\r')"
    local api_loaded
    api_loaded="$(printf '%s' "$loaded" | sed -n '2p' | tr -d '\r')"

    if [[ -z "$BASE_URL" && -n "$base_loaded" ]]; then
      BASE_URL="$base_loaded"
    fi
    if [[ -z "$FIREBASE_WEB_API_KEY" && -n "$api_loaded" ]]; then
      FIREBASE_WEB_API_KEY="$api_loaded"
    fi
  else
    # Best-effort fallback (shallow keys only).
    if [[ -z "$BASE_URL" ]]; then
      BASE_URL="$(sed -nE 's/.*"WEAFRICA_API_BASE_URL"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$ENV_PATH" | head -n 1)"
    fi
    if [[ -z "$FIREBASE_WEB_API_KEY" ]]; then
      FIREBASE_WEB_API_KEY="$(sed -nE 's/.*"FIREBASE_WEB_API_KEY"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$ENV_PATH" | head -n 1)"
    fi
  fi
}

load_env_json

# Normalize base URL for safe concatenation.
BASE_URL="${BASE_URL%/}"

if [[ -z "$BASE_URL" ]]; then
  echo "BASE_URL is required (e.g. https://<project-ref>.functions.supabase.co)" >&2
  echo "Tip: put WEAFRICA_API_BASE_URL in $ENV_PATH (see tool/supabase.env.json.example)." >&2
  exit 2
fi

if [[ "$BASE_URL" == *"YOUR_PROJECT_REF"* || "$BASE_URL" == *"YOUR_PROJECT"* ]]; then
  echo "BASE_URL looks like a placeholder: '$BASE_URL'" >&2
  echo "Set BASE_URL to your deployed Edge Functions base URL (e.g. https://<ref>.functions.supabase.co)." >&2
  exit 2
fi

echo "Using BASE_URL: $BASE_URL"
if [[ -n "$ENV_PATH" && -f "$ENV_PATH" ]]; then
  echo "Loaded env file: $ENV_PATH"
fi

pretty() {
  if [[ "$have_python" == "1" ]]; then
    python3 -m json.tool
  else
    cat
  fi
}

json_get() {
  local key="$1"; shift
  local raw="$1"; shift

  if [[ "$have_python" == "1" ]]; then
    python3 - "$key" "$raw" <<'PY'
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
    # best-effort fallback: supports only simple (non-nested) keys.
    echo "$raw" | sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"?([^\",}]*)\"?.*/\1/p" | head -n 1
  fi
}

firebase_login() {
  local email="$1"; shift
  local password="$1"; shift

  if [[ -z "$FIREBASE_WEB_API_KEY" ]]; then
    echo "Missing FIREBASE_WEB_API_KEY (or FIREBASE_API_KEY)." >&2
    exit 2
  fi
  if [[ "$FIREBASE_WEB_API_KEY" == "YOUR_FIREBASE_WEB_API_KEY" || "$FIREBASE_WEB_API_KEY" == "YOUR_FIREBASE_API_KEY" ]]; then
    echo "FIREBASE_WEB_API_KEY looks like a placeholder: '$FIREBASE_WEB_API_KEY'" >&2
    echo "Use the Firebase Console -> Project settings -> Web API Key." >&2
    exit 2
  fi
  if [[ -z "$email" || -z "$password" ]]; then
    echo "Missing Firebase login credentials for $email" >&2
    exit 2
  fi

  local url="https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_WEB_API_KEY}"

  set +e
  local resp
  resp="$(curl -sS -X POST "$url" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    --data "{\"email\":\"${email}\",\"password\":\"${password}\",\"returnSecureToken\":true}" \
    -w "\n%{http_code}")"
  local curl_ec=$?
  set -e
  if [[ "$curl_ec" != "0" ]]; then
    echo "Firebase auth request failed (curl exit $curl_ec)" >&2
    exit 1
  fi

  local code
  code="$(printf '%s' "$resp" | tail -n 1 | tr -d '\r')"
  local body
  body="$(printf '%s' "$resp" | sed '$d')"

  if [[ "$code" == "200" ]]; then
    local token
    token="$(json_get "idToken" "$body")"
    if [[ -n "$token" ]]; then
      echo "$token"
      return 0
    fi
    echo "Firebase auth succeeded but no idToken returned." >&2
    echo "$body" >&2
    exit 1
  fi

  local msg
  msg="$(json_get "error.message" "$body")"
  if [[ -z "$msg" ]]; then
    msg="$(json_get "message" "$body")"
  fi
  if [[ -z "$msg" ]]; then
    msg="$(json_get "error" "$body")"
  fi

  echo "Firebase auth failed for ${email}: ${msg:-HTTP_${code}}" >&2
  # Print body for debugging (common Firebase errors are safe: INVALID_API_KEY/INVALID_PASSWORD/etc.)
  if [[ -n "$body" ]]; then
    echo "$body" >&2
  fi
  exit 1
}

api_call() {
  local method="$1"; shift
  local path="$1"; shift
  local id_token="$1"; shift
  local body="${1:-}"

  local headers=("-H" "Accept: application/json")
  headers+=("-H" "Authorization: Bearer ${id_token}")
  if [[ -n "$TEST_TOKEN" ]]; then
    headers+=("-H" "x-weafrica-test-token: ${TEST_TOKEN}")
  fi

  if [[ "$method" == "GET" ]]; then
    curl -sS -X GET "${BASE_URL}${path}" "${headers[@]}" -w "\n%{http_code}"
  else
    curl -sS -X "$method" "${BASE_URL}${path}" "${headers[@]}" \
      -H "Content-Type: application/json" \
      --data "$body" \
      -w "\n%{http_code}"
  fi
}

print_section() {
  printf "\n== %s ==\n" "$1"
}

check_one() {
  local expected_role="$1"; shift
  local email="$1"; shift
  local password="$1"; shift
  local display_name="$1"; shift
  local provided_token="$1"; shift

  local role_upper
  role_upper="$(printf '%s' "$expected_role" | tr '[:lower:]' '[:upper:]')"
  print_section "${role_upper} (${email})"

  local token="$provided_token"
  if [[ -z "$token" ]]; then
    if [[ -z "$password" ]]; then
      read -r -s -p "Password for ${email}: " password
      echo
    fi
    token="$(firebase_login "$email" "$password")"
  fi

  printf -- "- role before:\n"
  local before
  before="$(api_call GET "/api/auth/role" "$token")"
  local before_code
  before_code="$(echo "$before" | tail -n 1)"
  local before_raw
  before_raw="$(echo "$before" | sed '$d')"
  if [[ "$before_code" != "200" ]]; then
    echo "$before_raw" >&2
    echo "HTTP ${before_code} calling /api/auth/role" >&2
    exit 1
  fi
  echo "$before_raw" | pretty

  printf -- "- provision (%s):\n" "$expected_role"
  local prov
  prov="$(api_call POST "/api/auth/provision-creator" "$token" "{\"intent\":\"${expected_role}\",\"display_name\":\"${display_name}\"}")"
  local prov_code
  prov_code="$(echo "$prov" | tail -n 1)"
  local prov_raw
  prov_raw="$(echo "$prov" | sed '$d')"
  if [[ "$prov_code" != "200" ]]; then
    echo "$prov_raw" >&2
    echo "HTTP ${prov_code} calling /api/auth/provision-creator" >&2
    exit 1
  fi
  echo "$prov_raw" | pretty

  printf -- "- role after:\n"
  local after
  after="$(api_call GET "/api/auth/role" "$token")"
  local after_code
  after_code="$(echo "$after" | tail -n 1)"
  local after_raw
  after_raw="$(echo "$after" | sed '$d')"
  if [[ "$after_code" != "200" ]]; then
    echo "$after_raw" >&2
    echo "HTTP ${after_code} calling /api/auth/role" >&2
    exit 1
  fi
  echo "$after_raw" | pretty

  # Minimal assertions (best-effort).
  local role_after
  role_after="$(json_get "role" "$after_raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "$role_after" != "$expected_role" ]]; then
    echo "ERROR: expected role '$expected_role' but got '${role_after:-<empty>}'" >&2
    exit 1
  fi

  if [[ "$expected_role" == "artist" ]]; then
    local artist_id
    artist_id="$(json_get "artist_id" "$prov_raw")"
    if [[ -z "$artist_id" || "$artist_id" == "null" ]]; then
      echo "ERROR: artist provision returned empty artist_id (artists backing row missing)." >&2
      exit 1
    fi
  fi

  if [[ "$expected_role" == "dj" ]]; then
    local dj_id
    dj_id="$(json_get "dj_id" "$prov_raw")"
    if [[ -z "$dj_id" || "$dj_id" == "null" ]]; then
      echo "WARNING: dj_id is empty. If uploads are gated by public.djs, DJ uploads may still be blocked." >&2
    fi
  fi

  echo "OK: ${expected_role} provision + role check passed."
}

check_one "artist" "$ARTIST_EMAIL" "$ARTIST_PASSWORD" "$ARTIST_DISPLAY_NAME" "$ARTIST_ID_TOKEN"
check_one "dj" "$DJ_EMAIL" "$DJ_PASSWORD" "$DJ_DISPLAY_NAME" "$DJ_ID_TOKEN"

print_section "Done"
echo "If DJ provisioning warns about dj_id=null, ensure your public.djs table supports firebase_uid and refresh schema cache."
