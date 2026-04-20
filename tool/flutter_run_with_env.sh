#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/tool/supabase.env.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  echo "Create it with: cp tool/supabase.env.json.example tool/supabase.env.json"
  echo "Then edit WEAFRICA_API_BASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY."
  exit 1
fi

cd "$ROOT_DIR"

# Pass all args through to flutter run (e.g., -d <deviceId>)
exec flutter run --dart-define-from-file=tool/supabase.env.json "$@"
