#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found in PATH. Install Android platform-tools and try again." >&2
  exit 1
fi

echo "== Restarting ADB =="
adb kill-server >/dev/null 2>&1 || true
adb start-server >/dev/null

list_devices() {
  adb devices -l | awk 'NR>1 && $1!="" {print}'
}

detect_device_id() {
  local ids
  ids="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"

  local count
  count="$(echo "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$count" == "0" ]]; then
    echo ""; return 0
  fi

  if [[ "$count" == "1" ]]; then
    echo "$ids" | head -n 1
    return 0
  fi

  echo "__MULTI__"
}

DEVICE_ID="${DEVICE_ID:-}"

print_troubleshooting() {
  echo "Troubleshooting quick checks:" >&2
  echo "- Use a data-capable USB cable (avoid charge-only cables)." >&2
  echo "- On the phone: enable Developer options + USB debugging." >&2
  echo "- Accept the 'Allow USB debugging' prompt, then retry." >&2
  echo "- Set USB mode to 'File transfer' (not 'Charging only')." >&2
  echo "- If it keeps dropping: try a different USB port/cable or use Wireless debugging." >&2
}

ensure_device_present() {
  local id="$1"
  if [[ -z "$id" ]]; then
    return 1
  fi

  if adb -s "$id" get-state >/dev/null 2>&1; then
    return 0
  fi

  echo "Device '$id' not reachable via adb. Restarting ADB..." >&2
  adb kill-server >/dev/null 2>&1 || true
  adb start-server >/dev/null 2>&1 || true

  # Give the USB connection a moment to re-enumerate.
  for _ in 1 2 3 4 5; do
    if adb -s "$id" get-state >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# Allow passing -d <id> through; we only auto-detect if no -d is provided.
HAS_D_FLAG=0
for arg in "$@"; do
  if [[ "$arg" == "-d" || "$arg" == "--device-id" ]]; then
    HAS_D_FLAG=1
    break
  fi
done

if [[ -z "$DEVICE_ID" && "$HAS_D_FLAG" == "0" ]]; then
  DEVICE_ID="$(detect_device_id)"
  if [[ "$DEVICE_ID" == "__MULTI__" ]]; then
    echo "Multiple devices detected. Re-run with -d <deviceId>." >&2
    echo
    echo "Connected devices:" >&2
    list_devices >&2
    exit 2
  fi

  if [[ -z "$DEVICE_ID" ]]; then
    echo "No Android devices detected by adb." >&2
    echo
    print_troubleshooting
    echo
    echo "adb devices output:" >&2
    adb devices -l >&2 || true
    exit 3
  fi

  if ! ensure_device_present "$DEVICE_ID"; then
    echo "Device '$DEVICE_ID' disconnected or unauthorized." >&2
    print_troubleshooting
    echo
    echo "adb devices output:" >&2
    adb devices -l >&2 || true
    exit 4
  fi

  echo "Auto-detected device: $DEVICE_ID"

  set +e
  "$ROOT_DIR/tool/flutter_run_with_env.sh" -d "$DEVICE_ID" "$@"
  RC=$?
  set -e

  if [[ "$RC" -ne 0 ]]; then
    echo >&2
    echo "flutter run failed (exit $RC)." >&2
    echo "adb devices after failure:" >&2
    adb devices -l >&2 || true

    # One-time retry if the device dropped during install/run.
    if ! adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
      echo >&2
      echo "Device '$DEVICE_ID' appears disconnected; retrying once after restarting ADB..." >&2
      adb kill-server >/dev/null 2>&1 || true
      adb start-server >/dev/null 2>&1 || true

      if ensure_device_present "$DEVICE_ID"; then
        APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
        RETRY_ARGS=()
        if [[ -f "$APK_PATH" ]]; then
          RETRY_ARGS=("--use-application-binary=$APK_PATH")
        fi

        "$ROOT_DIR/tool/flutter_run_with_env.sh" -d "$DEVICE_ID" "${RETRY_ARGS[@]}" "$@"
        exit $?
      fi
    fi

    exit "$RC"
  fi

  exit 0
fi

exec "$ROOT_DIR/tool/flutter_run_with_env.sh" "$@"
