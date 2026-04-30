#!/bin/bash
# Backup first
cp lib/features/shell/app_shell.dart lib/features/shell/app_shell.dart.backup

# Comment out broken notification imports
sed -i '' 's|import .notifications/notifications_screen.dart.;|// TODO: Fix - notifications_screen.dart removed|g' lib/features/shell/app_shell.dart
sed -i '' 's|import .notifications/services/announcements_store.dart.;|// TODO: Fix - announcements_store.dart removed|g' lib/features/shell/app_shell.dart  
sed -i '' 's|import .notifications/services/notification_center_store.dart.;|// TODO: Fix - notification_center_store.dart removed|g' lib/features/shell/app_shell.dart

# Comment out broken battle screen imports
sed -i '' 's|import .artist_dashboard/screens/artist_live_battles_screen.dart.;|// TODO: Fix - artist_live_battles_screen.dart removed|g' lib/features/shell/app_shell.dart
sed -i '' 's|import .dj_dashboard/screens/dj_live_battles_screen.dart.;|// TODO: Fix - dj_live_battles_screen.dart removed|g' lib/features/shell/app_shell.dart
sed -i '' 's|import .dj_dashboard/screens/dj_battle_history_screen.dart.;|// TODO: Fix - dj_battle_history_screen.dart removed|g' lib/features/shell/app_shell.dart
sed -i '' 's|import .dj_dashboard/screens/dj_stats_screen.dart.;|// TODO: Fix - dj_stats_screen.dart removed|g' lib/features/shell/app_shell.dart
