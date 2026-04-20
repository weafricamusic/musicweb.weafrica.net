#!/usr/bin/env bash
set -euo pipefail

# Builds Flutter web for hosting under a LocalWP (WordPress) site sub-path,
# then deploys it into the Local site document root.
#
# Default URL (with defaults below):
#   http://weafrica.local/weafrica_music_web/
#
# Usage:
#   ./tool/deploy_web_to_localwp.sh
#
# Overrides:
#   LOCAL_SITE_NAME=weafrica SUBDIR=weafrica_music_web ./tool/deploy_web_to_localwp.sh
#   LOCAL_PUBLIC_DIR="/Users/<you>/Local Sites/<site>/app/public" ./tool/deploy_web_to_localwp.sh

LOCAL_SITE_NAME=${LOCAL_SITE_NAME:-weafrica}
SUBDIR=${SUBDIR:-weafrica_music_web}
LOCAL_PUBLIC_DIR=${LOCAL_PUBLIC_DIR:-"$HOME/Local Sites/$LOCAL_SITE_NAME/app/public"}

# Must start/end with '/'
BASE_HREF="/${SUBDIR}/"

if [[ ! -d "$LOCAL_PUBLIC_DIR" ]]; then
  echo "LocalWP public dir not found: $LOCAL_PUBLIC_DIR" >&2
  echo "Set LOCAL_PUBLIC_DIR explicitly, e.g.:" >&2
  echo "  LOCAL_PUBLIC_DIR=\"$HOME/Local Sites/<site>/app/public\" $0" >&2
  exit 1
fi

echo "Building Flutter web with base href: $BASE_HREF"
flutter build web --release --base-href "$BASE_HREF"

# If the Local site uses Apache (some do), this helps SPA deep-links.
cat > build/web/.htaccess <<EOF
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase $BASE_HREF

  RewriteRule ^index\.html$ - [L]
  RewriteCond %{REQUEST_FILENAME} -f [OR]
  RewriteCond %{REQUEST_FILENAME} -d
  RewriteRule ^ - [L]

  RewriteRule . ${BASE_HREF}index.html [L]
</IfModule>
EOF

DEST_DIR="$LOCAL_PUBLIC_DIR/$SUBDIR"
mkdir -p "$DEST_DIR"

echo "Deploying to: $DEST_DIR"
rsync -a --delete "build/web/" "$DEST_DIR/"

url="http://${LOCAL_SITE_NAME}.local${BASE_HREF}"

echo "Done. Open: $url"
echo

echo "If your LocalWP site is set to Apache, .htaccess will handle SPA deep-links."
echo "If your LocalWP site is set to Nginx, .htaccess is ignored and you need an Nginx try_files rule for ${BASE_HREF}."
