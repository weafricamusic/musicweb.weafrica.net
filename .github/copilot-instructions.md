# GitHub Copilot / AI Agent Instructions for WeAfrica Music

Purpose: help AI coding agents become productive quickly in this repository by summarizing architecture, developer flows, and project-specific patterns.

Quick links

- Repo root README: [README.md](README.md)
- Flutter entry points: [lib/main.dart](lib/main.dart)
- Android: [android/](android/)
- iOS: [ios/](ios/)
- Docs (notifications, push, smoke tests): [docs/](docs/)
- Scripts: [run_smoke_test.sh](run_smoke_test.sh)
- Firebase helper: [get-firebase-id-token.mjs](get-firebase-id-token.mjs)

Big-picture architecture (what to know first)

- This is a Flutter app with platform-specific native integrations: Android in `/android`, iOS in `/ios`, macOS in `/macos`.
- Flutter code organizes features under `/lib` into layered folders: `app`, `core`, `data`, `features`, `services`, `shared`, and `ui`. Use these as boundaries for responsibilities:
  - `lib/data`: data models, repositories and data sources.
  - `lib/services`: platform / backend integrations (e.g., network, push, analytics).
  - `lib/features`: UI screens and feature-specific logic.
  - `lib/core` and `lib/shared`: app-wide utilities and common widgets.
- Serverless / backend code lives in `/functions` and `/supabase/functions` — integrations with Firebase, Supabase, and other cloud services are present.
- Notifications and push logic are heavily documented in `/docs`. Many tasks (smoke tests, analytics) rely on native config & Firebase tokens.

Key integration points

- Firebase: several docs and helper scripts exist (`get-firebase-id-token.mjs`, many docs under `docs/`). When changing push/notification code, update docs and smoke test scripts.
- Agora: native SDK artifacts exist under `build/` and `/assets/agora_rtc_engine`. Changes to real-time audio/video must touch native build configs.
- Supabase: `supabase/` contains edge functions and migrations — treat these as a separate deployment artifact.
- Native config: `android/key.properties.example` and `local.properties` are used for sensitive values; do not hardcode keys in Dart sources.

Developer flows you should use or suggest

- Local Flutter analysis and build:
  - Fetch deps: `flutter pub get`
  - Static analysis: `flutter analyze` (fix or explain any analyzer warnings before large changes)
  - Run app: `flutter run -d <device>` or `flutter run` from repo root
  - Build Android APK: `flutter build apk`
- Native / platform work:
  - Open Android in Android Studio using `android/` Gradle project.
  - Open iOS in Xcode via `ios/Runner.xcworkspace` for signing/capability changes.
- Smoke tests & scripts:
  - There's a top-level `run_smoke_test.sh` that wires several checks; review before changing notification flows.
- Testing:
  - Unit/widget tests: `flutter test`.
  - The repo contains multiple test entry points (`test/`), run targeted tests for the area you change.

Project-specific conventions and patterns

- Namespaces & layering: prefer placing logic in `lib/features/<feature>` for feature-scoped logic and `lib/services` for cross-feature services.
- Repository code favors small repository/data-source classes in `lib/data` — changes to data models often require corresponding repository and service updates.
- Documentation-first for notifications: the docs in `docs/` are canonical for how push/analytics are wired. When you modify notification behavior, update the relevant doc(s): e.g., `docs/PUSH_NOTIFICATION_SETUP.md`, `docs/PUSH_NOTIFICATION_IMPLEMENTATION.md`.
- Secrets and platform keys: never add real keys in repo; use `android/key.properties` and CI secrets.

Patterns to follow when editing code

- Keep UI code in `lib/features/<name>/screens` and business logic in `lib/features/<name>/bloc|controller|viewmodel` depending on the feature structure.
- Prefer adding new services under `lib/services` and registering them with the app bootstrap code (look at `lib/app` / `lib/main.dart` for initialization points).
- When modifying native platform code, update Gradle and Podfile changes appropriately and test with an actual device or emulator.

Files that are good examples to read before coding

- App entry and bootstrap: [lib/main.dart](lib/main.dart)
- Notification integration docs: [docs/PUSH_NOTIFICATION_SETUP.md](docs/PUSH_NOTIFICATION_SETUP.md)
- Smoke test orchestration: [run_smoke_test.sh](run_smoke_test.sh)
- Firebase helper: [get-firebase-id-token.mjs](get-firebase-id-token.mjs)
- Android example secrets: [android/key.properties.example](android/key.properties.example)

What NOT to change lightly

- `pubspec.yaml` dependency versions — coordinate with CI and test all platforms when upgrading Flutter or major packages.
- Native signing files and CI secrets.
- Notification docs without running the smoke tests in `run_smoke_test.sh`.

If you need to make a PR

- Keep changes scoped to a single concern (feature, bugfix, docs).
- Run `flutter analyze` and `flutter test` locally and include results in the PR description if non-trivial.
- Update any affected docs in `docs/` and add or update smoke tests where appropriate.

Questions for the repo owner

- Are there any CI/CD steps or secrets not included in this repo that AI agents should be aware of? (e.g., API keys or deployment steps for `supabase/` or `functions/`)
- Preferred state-management pattern for new features? (I observed mixed patterns under `lib/features`.)

Please review this draft and tell me which areas need more detail or examples; I can iterate quickly.
