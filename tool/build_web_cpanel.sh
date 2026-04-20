#!/usr/bin/env bash
set -euo pipefail

# Builds Flutter web and prepares output for cPanel/Apache static hosting.
# - Ensures correct base href for root-domain hosting.
# - Copies Apache SPA rewrite rules (.htaccess) into build output.

WEB_DOMAIN=${WEB_DOMAIN:-musicweb.weafrica.net}
ZIP_NAME=${ZIP_NAME:-weafrica_music_web_cpanel.zip}
ENV_JSON=${ENV_JSON:-assets/config/supabase.env.json}

assert_not_service_account_json() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  if grep -Eq '"private_key"[[:space:]]*:|"type"[[:space:]]*:[[:space:]]*"service_account"|BEGIN PRIVATE KEY' "$path"; then
    echo "ERROR: $path appears to contain a Google service account key (private_key)." >&2
    echo "Do NOT embed service-account JSON into a client build via --dart-define-from-file." >&2
    exit 1
  fi
}

assert_no_service_role_key() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  if grep -Eq '"SUPABASE_SERVICE_ROLE_KEY"[[:space:]]*:' "$path"; then
    echo "ERROR: $path contains SUPABASE_SERVICE_ROLE_KEY." >&2
    echo "Do NOT ship Supabase service_role keys in a client web build." >&2
    exit 1
  fi
}

build_args=(--release --base-href / --no-wasm-dry-run)

if [[ -f "$ENV_JSON" ]]; then
  assert_not_service_account_json "$ENV_JSON"
  assert_no_service_role_key "$ENV_JSON"
  build_args+=("--dart-define-from-file=$ENV_JSON")
  echo "Using dart-defines from $ENV_JSON"
else
  echo "Warning: $ENV_JSON not found; building without --dart-define-from-file." >&2
fi

flutter build web "${build_args[@]}"

if [[ -f "web/.htaccess" ]]; then
  cp "web/.htaccess" "build/web/.htaccess"
  echo "Copied web/.htaccess -> build/web/.htaccess"
else
  echo "Warning: web/.htaccess not found; deep links may 404 on refresh." >&2
fi

zip_path="build/$ZIP_NAME"
rm -f "$zip_path"
(
  cd build/web
  # Package the deployable web root (includes dotfiles like .htaccess).
  zip -qr "../$ZIP_NAME" . -x "*.DS_Store"
)

echo "Web build ready in build/web"
echo "ZIP ready: $zip_path"
echo "Deploy target: https://$WEB_DOMAIN/"
