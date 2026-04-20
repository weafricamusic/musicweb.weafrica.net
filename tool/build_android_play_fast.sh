#!/usr/bin/env bash
set -euo pipefail

# Fast Play build path (much quicker than full optimized build).
# Use this for quick validation/internal upload, then run the small optimized
# build script before final production rollout.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

flutter build appbundle \
  --release \
  --target-platform android-arm64

echo "Built: build/app/outputs/bundle/release/app-release.aab"
