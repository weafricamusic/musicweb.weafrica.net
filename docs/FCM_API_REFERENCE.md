# FCM API Reference (Notes)

This document replaces the old Flutter-side reference file that previously lived at:
- `lib/features/notifications/FCM_API_REFERENCE.dart`

That Dart file contained mixed snippet/reference code and was being picked up by `flutter analyze`, causing production builds to fail.

## Where the real implementation lives
- `lib/services/notification_service.dart` (app-side notification handling)
- `functions/src/deviceTokens.ts` (token registration)
- `functions/src/notifications.ts` (sending notifications)

## Recommendation
Keep any future reference snippets in `docs/` (Markdown), not under `lib/`, unless they compile and are used by the app.
