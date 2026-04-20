#!/usr/bin/env bash
set -euo pipefail

# Build a smaller Play Store app bundle.
# - Obfuscate Dart symbols and split debug info out of the bundle.
# - Restrict target platforms to ARM only.
# - Use release mode.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYMBOL_DIR="$ROOT_DIR/build/symbols/android"

mkdir -p "$SYMBOL_DIR"

cd "$ROOT_DIR"
flutter build appbundle \
  --release \
  --target-platform android-arm,android-arm64 \
  --obfuscate \
  --split-debug-info="$SYMBOL_DIR"

echo "Built: build/app/outputs/bundle/release/app-release.aab"
echo "Symbols: $SYMBOL_DIR"
