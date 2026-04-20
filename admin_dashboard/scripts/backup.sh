#!/usr/bin/env bash
set -euo pipefail

# Simple weekly export helper for Supabase (schema + data)
# Requires: supabase CLI and a linked project (supabase link)

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="backups/$TS"
mkdir -p "$OUT_DIR"

echo "→ Dumping schema..."
supabase db dump --schema public --file "$OUT_DIR/schema.sql"

echo "→ Dumping data (selected tables)..."
TABLES=(users artists djs transactions coins withdrawals admin_audit_logs)
for t in "${TABLES[@]}"; do
  supabase db dump --data-only --table "$t" --file "$OUT_DIR/${t}.sql" || true
done

echo "✓ Backup written to $OUT_DIR"
