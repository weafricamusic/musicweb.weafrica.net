# Google Play Store release checklist (Android)

This project is already close to Play-Store-ready. This doc is a practical checklist to get a **signed release App Bundle (AAB)** and avoid common Play Console rejections.

## 1) Versioning (required)

- Update the Flutter app version in `pubspec.yaml`:
  - `version: x.y.z+N`
  - `x.y.z` becomes Android `versionName`
  - `N` becomes Android `versionCode`

Example:
- `version: 1.0.1+2`

## 2) Release signing (required)

Google Play requires a **non-debug** signing key.

1. Generate an upload keystore (keep it secret and backed up):

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

2. Place the keystore at:
- `android/upload-keystore.jks`

3. Create `android/key.properties` by copying the template:
- Copy: `android/key.properties.example` → `android/key.properties`
- Fill in the real passwords

Notes:
- `android/key.properties` is **already git-ignored**.

## 3) Build a release AAB (required)

From repo root:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Output:
- `build/app/outputs/bundle/release/app-release.aab`

## 4) Manifest & network security (Play review)

- Release manifest uses:
  - `android:usesCleartextTraffic="false"` (good)
- Debug manifest enables cleartext for development only (good)

If you add any HTTP (non-HTTPS) endpoints in production, Play may flag it and users’ networks may block it.

## 5) Permissions (Play Console declarations)

Current main manifest declares (common in audio/social apps):
- `INTERNET`
- `POST_NOTIFICATIONS`
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `WAKE_LOCK`
- `RECEIVE_BOOT_COMPLETED`
- `CAMERA`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`

Play Console requirements:
- Provide an in-app explanation for sensitive permissions (camera/mic) and ensure you only request them when needed.
- Fill in the Play Console “Permissions Declaration Form” if prompted.

## 6) Play Console non-code requirements

These are required to pass review but aren’t solved purely by code:
- **Privacy Policy URL** (hosted, public)
- Data safety form (what data is collected/shared)
- Content rating questionnaire
- Store listing assets (icon, feature graphic, screenshots)
- Support email/website

## 7) Recommended final smoke checks

- Install the release build on a device and test:
  - Login/signup
  - Home loads without crashes
  - Music playback (background + notification)
  - Push notifications (if Firebase configured)
  - Upload flows (camera/mic)

Helpful commands:

```bash
flutter build apk --release
flutter install
```

## 8) Common blockers and what to do

- "App is signed with debug key":
  - Ensure `android/key.properties` exists and points to your `.jks`
- "Target API level" warnings:
  - Ensure Flutter/AGP is using the latest target SDK required by Google Play
- Minify/shrink issues:
  - If release crashes only in minified builds, temporarily set `isMinifyEnabled = false` to diagnose, then add keep rules in `android/app/proguard-rules.pro`.
