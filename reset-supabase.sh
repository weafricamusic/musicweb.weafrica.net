#!/bin/bash

set -euo pipefail

# Always run from the repo root (directory containing this script).
cd "$(dirname "$0")"

echo "Stopping Supabase..."
supabase stop

echo "Removing containers..."
docker rm -f $(docker ps -a -q --filter "label=com.supabase.cli.project=weafrica_music") 2>/dev/null || true

echo "Removing volumes..."
docker volume rm $(docker volume ls -q --filter "label=com.supabase.cli.project=weafrica_music") 2>/dev/null || true

echo "Setting Docker API version..."
export DOCKER_API_VERSION=1.54

echo "Starting Supabase fresh..."
supabase start \
	--exclude storage-api \
	--exclude logflare \
	--exclude realtime \
	--exclude studio \
	--exclude postgres-meta \
	--ignore-health-check \
	--debug

echo "Checking status..."
sleep 5
supabase status
