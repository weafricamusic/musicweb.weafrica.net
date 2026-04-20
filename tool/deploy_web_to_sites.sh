#!/usr/bin/env bash
set -euo pipefail

# Deploy Flutter web build output to macOS Apache "User Sites" (~/Sites).
# Default local URL:
#   http://localhost/~$(whoami)/weafrica_music/
#
# Usage:
#   ./tool/build_web_cpanel.sh
#   ./tool/deploy_web_to_sites.sh
#
# Optional env overrides:
#   SITE_SUBDIR=weafrica_music SRC_DIR=build/web SITES_DIR="$HOME/Sites" ./tool/deploy_web_to_sites.sh

SITE_SUBDIR=${SITE_SUBDIR:-weafrica_music}
SRC_DIR=${SRC_DIR:-build/web}
SITES_DIR=${SITES_DIR:-"$HOME/Sites"}

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Build output not found at: $SRC_DIR" >&2
  echo "Run: ./tool/build_web_cpanel.sh" >&2
  exit 1
fi

dest_dir="$SITES_DIR/$SITE_SUBDIR"

mkdir -p "$dest_dir"

# Use rsync for fast incremental deploys and to keep the folder clean.
rsync -a --delete "$SRC_DIR/" "$dest_dir/"

user="$(whoami)"
url="http://localhost/~$user/$SITE_SUBDIR/"

echo "Deployed to: $dest_dir"
echo "Local URL:  $url"

echo
if pgrep -x "httpd" >/dev/null 2>&1; then
  echo "Apache appears to be running (httpd)."
else
  echo "Apache does not appear to be running. Start it with: sudo apachectl start"
fi

echo "If you get 403/404 on the URL, you likely need to enable UserDir (~username) in /etc/apache2/httpd.conf and allow overrides for .htaccess."
