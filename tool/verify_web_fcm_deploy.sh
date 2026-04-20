#!/usr/bin/env bash
set -euo pipefail

# Verify production web deployment for Firebase Messaging service worker.
# Usage:
#   ./tool/verify_web_fcm_deploy.sh
#   WEB_URL=https://musicweb.weafrica.net ./tool/verify_web_fcm_deploy.sh

WEB_URL=${WEB_URL:-https://musicweb.weafrica.net}

check_headers() {
  local path="$1"
  echo "--- $path ---"
  curl -sSI "$WEB_URL$path" | sed -n '1,8p'
  echo
}

check_body_head() {
  local path="$1"
  echo "--- body $path ---"
  curl -sS "$WEB_URL$path" | head -n 6
  echo
}

check_headers "/index.html"
check_headers "/flutter_bootstrap.js"
check_headers "/firebase-messaging-sw.js"
check_body_head "/firebase-messaging-sw.js"

echo "Expected: /firebase-messaging-sw.js => HTTP 200 and JS content (not 404 HTML)."
