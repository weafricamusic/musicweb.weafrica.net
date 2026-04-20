#!/usr/bin/env bash
set -euo pipefail

# Deploy Flutter web build to cPanel via FTPS (port 21 by default).
#
# Required env vars:
#   CPANEL_FTP_HOST
#   CPANEL_FTP_USER
#   CPANEL_FTP_PASSWORD
#
# Optional env vars:
#   CPANEL_FTP_PORT (default 21)
#   SRC_DIR         (default build/web)
#   REMOTE_DIR      (default /public_html/music)
#   BUILD_FIRST     (default 1)
#   DELETE_STALE    (default 0)
#   FTPS_INSECURE   (default 0)

BUILD_FIRST=${BUILD_FIRST:-1}
DELETE_STALE=${DELETE_STALE:-0}
FTPS_INSECURE=${FTPS_INSECURE:-0}
SRC_DIR=${SRC_DIR:-build/web}

if [[ "$BUILD_FIRST" == "1" ]]; then
  bash tool/build_web_cpanel.sh
fi

args=(
  --src "$SRC_DIR"
  --remote-dir "${REMOTE_DIR:-/public_html/music}"
)

if [[ "$DELETE_STALE" == "1" ]]; then
  args+=(--delete)
fi

if [[ "$FTPS_INSECURE" == "1" ]]; then
  args+=(--insecure)
fi

python3 tool/deploy_web_cpanel_ftps.py "${args[@]}"
