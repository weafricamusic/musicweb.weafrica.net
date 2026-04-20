#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_JSON_DEFAULT="$ROOT_DIR/assets/config/supabase.env.json"
ENV_JSON="${ENV_JSON:-$ENV_JSON_DEFAULT}"

DEVICE_ID="${DEVICE_ID:-}"

CLEAN_BUILD=0
RUN_BACKEND_SMOKES=1
RUN_INTEGRATION=1

usage() {
  cat <<'USAGE'
Runs a practical "80% coverage" test pipeline for WeAfrica Music:
  1) flutter pub get
  2) flutter analyze
  3) flutter test (unit/widget)
  4) backend smoke checks (optional)
  5) flutter test integration_test/* (on a device)

Usage:
  bash tool/run_full_tests.sh [--clean] [--no-backend] [--no-integration] [--device <id>] [--env <path>]

Env vars:
  ENV_JSON=assets/config/supabase.env.json   (default)
  DEVICE_ID=<flutter device id>

Backend creator-role smoke test (optional):
  Provide either ARTIST_EMAIL + ARTIST_PASSWORD and DJ_EMAIL + DJ_PASSWORD
  OR ARTIST_ID_TOKEN and DJ_ID_TOKEN.

Notes:
- Prefer ENV_JSON that only contains public client-safe values (SUPABASE_ANON_KEY, etc).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --clean)
      CLEAN_BUILD=1
      shift
      ;;
    --no-backend)
      RUN_BACKEND_SMOKES=0
      shift
      ;;
    --no-integration)
      RUN_INTEGRATION=0
      shift
      ;;
    --device)
      DEVICE_ID="${2:-}"
      if [[ -z "$DEVICE_ID" ]]; then
        echo "Missing value for --device" >&2
        exit 2
      fi
      shift 2
      ;;
    --env)
      ENV_JSON="${2:-}"
      if [[ -z "$ENV_JSON" ]]; then
        echo "Missing value for --env" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ ! -f "$ENV_JSON" ]]; then
  echo "Missing ENV_JSON file: $ENV_JSON" >&2
  echo "Tip: set ENV_JSON=assets/config/supabase.env.json" >&2
  exit 2
fi

if [[ "$CLEAN_BUILD" == "1" ]]; then
  echo "==> flutter clean"
  flutter clean
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (unit/widget)"
flutter test

if [[ "$RUN_BACKEND_SMOKES" == "1" ]]; then
  echo "==> dart run tool/subscriptions_smoke_test.dart"
  dart run tool/subscriptions_smoke_test.dart "$ENV_JSON"

  # Creator role/provisioning smoke test requires credentials or tokens.
  if [[ -n "${ARTIST_ID_TOKEN:-}" && -n "${DJ_ID_TOKEN:-}" ]] ||
     ([[ -n "${ARTIST_PASSWORD:-}" && -n "${DJ_PASSWORD:-}" ]]); then
    echo "==> bash tool/creator_role_smoke_test.sh"
    ENV_PATH="$ENV_JSON" bash tool/creator_role_smoke_test.sh
  else
    echo "==> (skip) creator_role_smoke_test (missing ARTIST/DJ creds or tokens)"
  fi
fi

if [[ "$RUN_INTEGRATION" != "1" ]]; then
  echo "==> Skipping integration tests (--no-integration)"
  echo "✅ Done"
  exit 0
fi

pick_device() {
  python3 - <<'PY'
import json, subprocess, sys

raw = subprocess.check_output(['flutter', 'devices', '--machine'], text=True)
try:
  devices = json.loads(raw)
except Exception:
  devices = []

# Prefer Android (physical or emulator), then iOS, then desktop.
priority = (
  lambda d: 0 if str(d.get('targetPlatform','')).startswith('android') else
            1 if str(d.get('targetPlatform','')).startswith('ios') else
            2 if str(d.get('id','')) in ('macos','windows','linux') or str(d.get('targetPlatform','')).startswith('darwin') else
            9
)

candidates = [d for d in devices if d.get('isSupported')]
# Avoid web by default.
candidates = [d for d in candidates if str(d.get('targetPlatform','')) != 'web-javascript']

candidates.sort(key=priority)

if not candidates:
  sys.exit(1)

print(candidates[0].get('id',''))
PY
}

if [[ -z "$DEVICE_ID" ]]; then
  if DEVICE_ID="$(pick_device 2>/dev/null)"; then
    :
  else
    echo "No non-web supported device found for integration tests." >&2
    echo "Connect an Android device or start an emulator, then re-run." >&2
    exit 2
  fi
fi

echo "==> flutter test integration_test (device=$DEVICE_ID)"
INTEG_ARGS=(
  -d "$DEVICE_ID"
  --dart-define-from-file="$ENV_JSON"
)

# Optional E2E creds for tests like integration_test/e2e_login_test.dart.
# Provide them as environment variables when invoking this script.
if [[ -n "${E2E_TEST_EMAIL:-}" ]]; then
  INTEG_ARGS+=(--dart-define=E2E_TEST_EMAIL="$E2E_TEST_EMAIL")
fi
if [[ -n "${E2E_TEST_PASSWORD:-}" ]]; then
  INTEG_ARGS+=(--dart-define=E2E_TEST_PASSWORD="$E2E_TEST_PASSWORD")
fi

flutter test "${INTEG_ARGS[@]}" integration_test

echo "✅ Done"
