#!/bin/bash

echo "Fixing postgrest compatibility issues..."

# Fix live_discovery_service.dart
if [ -f "lib/features/live/services/live_discovery_service.dart" ]; then
  sed -i '' 's/\.limit(\([^)]*\));$/);\n  if (\1 > 0) {\n    query = query.limit(\1);\n  }/g' lib/features/live/services/live_discovery_service.dart
  echo "✓ Fixed live_discovery_service.dart"
fi

# Fix artist_stats_repository.dart
if [ -f "lib/features/artist/dashboard/repositories/artist_stats_repository.dart" ]; then
  sed -i '' "s/\.select('id', count: 'exact')/.select('id')/g" lib/features/artist/dashboard/repositories/artist_stats_repository.dart
  echo "✓ Fixed artist_stats_repository.dart"
fi

echo "Done! Run 'flutter clean && flutter pub get && flutter run'"
