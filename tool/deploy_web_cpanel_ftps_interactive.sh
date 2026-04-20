#!/usr/bin/env bash
set -euo pipefail

# Interactive FTPS deploy helper for cPanel.
# Prompts securely for credentials, deploys build/web to /public_html/music,
# then runs live verification checks.

echo "=== WeAfrica cPanel FTPS deploy ==="
read -rp "FTP host (e.g. ftp.musicweb.weafrica.net): " CPANEL_FTP_HOST
read -rp "FTP user: " CPANEL_FTP_USER
read -rsp "FTP password: " CPANEL_FTP_PASSWORD
echo

read -rp "Remote dir [/public_html/music]: " REMOTE_DIR_INPUT
REMOTE_DIR=${REMOTE_DIR_INPUT:-/public_html/music}

read -rp "Rebuild web first? [Y/n]: " REBUILD_INPUT
REBUILD_INPUT=${REBUILD_INPUT:-Y}
if [[ "$REBUILD_INPUT" =~ ^[Yy]$ ]]; then
  BUILD_FIRST=1
else
  BUILD_FIRST=0
fi

read -rp "Delete stale remote files? [y/N]: " DELETE_INPUT
DELETE_INPUT=${DELETE_INPUT:-N}
if [[ "$DELETE_INPUT" =~ ^[Yy]$ ]]; then
  DELETE_STALE=1
else
  DELETE_STALE=0
fi

read -rp "Use insecure TLS (only if cert handshake fails)? [y/N]: " INSECURE_INPUT
INSECURE_INPUT=${INSECURE_INPUT:-N}
if [[ "$INSECURE_INPUT" =~ ^[Yy]$ ]]; then
  FTPS_INSECURE=1
else
  FTPS_INSECURE=0
fi

CPANEL_FTP_HOST="$CPANEL_FTP_HOST" \
CPANEL_FTP_USER="$CPANEL_FTP_USER" \
CPANEL_FTP_PASSWORD="$CPANEL_FTP_PASSWORD" \
REMOTE_DIR="$REMOTE_DIR" \
BUILD_FIRST="$BUILD_FIRST" \
DELETE_STALE="$DELETE_STALE" \
FTPS_INSECURE="$FTPS_INSECURE" \
./tool/deploy_web_cpanel_ftps.sh

echo
./tool/verify_web_fcm_deploy.sh
