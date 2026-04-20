#!/usr/bin/env bash
set -euo pipefail

# Deploy Flutter web build to cPanel via SFTP/SSH (rsync).
#
# Required env vars:
#   CPANEL_HOST      e.g. musicweb.weafrica.net or server hostname
#   CPANEL_USER      cPanel/SSH username
#
# Optional env vars:
#   CPANEL_PORT      default: 22
#   REMOTE_DIR       default: /home/$CPANEL_USER/public_html/music
#   SRC_DIR          default: build/web
#   BUILD_FIRST      default: 1 (build before deploy)
#
# Examples:
#   CPANEL_HOST=musicweb.weafrica.net CPANEL_USER=myuser ./tool/deploy_web_cpanel_sftp.sh
#   CPANEL_HOST=server.host.tld CPANEL_USER=myuser REMOTE_DIR=/home/myuser/public_html/music BUILD_FIRST=0 ./tool/deploy_web_cpanel_sftp.sh

CPANEL_HOST=${CPANEL_HOST:-}
CPANEL_USER=${CPANEL_USER:-}
CPANEL_PORT=${CPANEL_PORT:-22}
SRC_DIR=${SRC_DIR:-build/web}
BUILD_FIRST=${BUILD_FIRST:-1}
REMOTE_DIR=${REMOTE_DIR:-}

if [[ -z "$CPANEL_HOST" || -z "$CPANEL_USER" ]]; then
  echo "Missing required env vars: CPANEL_HOST and CPANEL_USER" >&2
  exit 1
fi

if [[ -z "$REMOTE_DIR" ]]; then
  REMOTE_DIR="/home/$CPANEL_USER/public_html/music"
fi

if [[ "$BUILD_FIRST" == "1" ]]; then
  echo "Building web bundle..."
  bash tool/build_web_cpanel.sh
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source build folder not found: $SRC_DIR" >&2
  exit 1
fi

echo "Deploying $SRC_DIR -> $CPANEL_USER@$CPANEL_HOST:$REMOTE_DIR"

ssh_opts=(-p "$CPANEL_PORT" -o StrictHostKeyChecking=accept-new)

# Ensure destination exists.
ssh "${ssh_opts[@]}" "$CPANEL_USER@$CPANEL_HOST" "mkdir -p '$REMOTE_DIR'"

# Sync files and delete removed files for clean deploy.
rsync -az --delete -e "ssh -p $CPANEL_PORT -o StrictHostKeyChecking=accept-new" \
  "$SRC_DIR/" "$CPANEL_USER@$CPANEL_HOST:$REMOTE_DIR/"

echo "Deployment complete."
echo "Run verification:"
echo "  curl -sSI https://musicweb.weafrica.net/firebase-messaging-sw.js | sed -n '1,8p'"
echo "  curl -sS  https://musicweb.weafrica.net/firebase-messaging-sw.js | head -n 8"
