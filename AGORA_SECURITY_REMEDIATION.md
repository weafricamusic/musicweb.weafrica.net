# ⚠️ URGENT: Agora Security Remediation Required

## Issue Summary

Your Agora **App Certificate** was exposed in the following locations:

1. `web/agora-vanilla-quickstart/.env` — contains the real certificate
2. `web/agora-vanilla-quickstart/index.html` — contains the real **App ID**
3. `lib/app/config/app_env.dart` (old version) — contained the real **App ID**
4. `lib/features/live/core/constants/agora_constants.dart` (old version) — contained a **different** App ID

## Immediate Actions Required

### 1. Rotate Your Agora App Certificate (DO THIS NOW)

The App Certificate is a **secret key** that allows anyone to generate valid tokens for your Agora project. If it was ever committed to Git or shared, it is compromised.

**Steps:**
1. Go to https://console.agora.io
2. Select your project
3. Go to **Project Management** → click your project
4. Find **Primary Certificate** and click **Enable / Reset**
5. Copy the **new** certificate
6. Update ONLY these files:
   - `backend/.env` → `AGORA_APP_CERTIFICATE=new_certificate`
   - `web/agora-vanilla-quickstart/.env` → `AGORA_APP_CERTIFICATE=new_certificate`
7. **Delete the old certificate from Agora Console** (it cannot be recovered, which is the point)

### 2. Verify Git History (Check if secrets were committed)

```bash
# Check if the certificate was ever committed
git log --all --full-history -- web/agora-vanilla-quickstart/.env
git log -p --all -- web/agora-vanilla-quickstart/.env | grep -i "certificate"

# If YES, you MUST rotate the certificate AND scrub Git history:
# Option A: Use BFG Repo-Cleaner (recommended)
#   https://rtyley.github.io/bfg-repo-cleaner/
# Option B: Use git-filter-repo
#   pip install git-filter-repo
#   git filter-repo --replace-text <(echo 'OLD_CERT=>NEW_CERT')
```

### 3. Secure Your Local Files

The following files have been updated to prevent future leaks:

- `.gitignore` — now ignores `backend/.env` and `web/agora-vanilla-quickstart/.env`
- `backend/.env.example` — template showing what env vars are needed (no real values)
- `web/agora-vanilla-quickstart/.env.example` — already existed, make sure to use it

### 4. Build-Time App ID Injection (Recommended)

Instead of hardcoding the App ID in Dart files, inject it at build time:

```bash
# Development
flutter run --dart-define=AGORA_APP_ID=your_real_app_id

# Production build
flutter build web --dart-define=AGORA_APP_ID=your_real_app_id
flutter build apk --dart-define=AGORA_APP_ID=your_real_app_id
flutter build ios --dart-define=AGORA_APP_ID=your_real_app_id
```

The updated `lib/app/config/app_env.dart` now reads from `--dart-define` first, then falls back to the compile-time value.

### 5. Token Server Endpoint Configuration

The token server URL is also injectable at build time:

```bash
flutter run \
  --dart-define=AGORA_APP_ID=your_app_id \
  --dart-define=AGORA_TOKEN_SERVER_URL=https://your-backend.com/api/agora/tokens/rtc
```

Or set it in your CI/CD pipeline:
```yaml
# .github/workflows/build.yml example
- run: flutter build web --release
    --dart-define=AGORA_APP_ID=${{ secrets.AGORA_APP_ID }}
    --dart-define=AGORA_TOKEN_SERVER_URL=${{ secrets.AGORA_TOKEN_SERVER_URL }}
```

## What Was Fixed in This Update

### Token Server (`backend/src/api/agora.js`)
- ✅ Now requires `Authorization: Bearer <token>` header (Firebase ID token)
- ✅ Validates `AGORA_APP_ID` length (32 chars) and `AGORA_APP_CERTIFICATE` minimum length
- ✅ Sanitizes channel names (alphanumeric, underscore, hyphen only)
- ✅ Clamps token TTL to max 24 hours
- ✅ Logs token generation with IP for auditing (never logs the certificate)
- ✅ Uses `agora-token` (AccessToken2 / v2) format

### Flutter Client
- ✅ `AgoraTokenService` — unified token fetching with Firebase auth, caching, and validation
- ✅ `AppEnv` — single source of truth for App ID with `--dart-define` support
- ✅ `AgoraConstants` — now delegates to `AppEnv` (no more hardcoded second App ID)
- ✅ `AgoraWebEngine` — fetches tokens via authenticated POST to production backend
- ✅ `AgoraMobileEngine` — fetches tokens via authenticated POST to production backend
- ✅ `LiveSessionCubit` — fetches token BEFORE joining and passes it to the engine

### App ID Validation
Every SDK initialization now validates:
- App ID is not empty
- App ID is exactly 32 characters after trimming
- Redacted logging (`XXXX...XXXX`) in debug mode — never logs full value

## Testing the Full Flow

### 1. Start the backend token server locally
```bash
cd backend
npm install  # if not already installed
cp .env.example .env
# Edit .env with your REAL (newly rotated) credentials
npm run dev   # or: node src/server.js
```

### 2. Test the token endpoint with curl
```bash
curl -X POST http://localhost:3000/api/agora/tokens/rtc \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_FIREBASE_ID_TOKEN" \
  -d '{"channelName":"test","role":"broadcaster","uid":123}'
```

### 3. Run Flutter with proper env vars
```bash
cd ..
flutter run -d chrome \
  --dart-define=AGORA_APP_ID=your_app_id \
  --dart-define=AGORA_TOKEN_SERVER_URL=http://localhost:3000/api/agora/tokens/rtc
```

### 4. Verify in browser console
You should see:
```
📋 AgoraTokenService — App ID validated: 21a9...39af (len=32)
🔑 AgoraTokenService — POST http://localhost:3000/api/agora/tokens/rtc
🔑 AgoraTokenService — token fetched (xxx chars)
✅ [Web] Joined channel: solo_...
🎬 [Web] LIVE STREAM ACTIVE!
```

## Questions?

If you see `INVALID_PARAMS: Invalid appid` or `401 Unauthorized`:
1. Check the App ID is 32 chars exactly (no spaces, no quotes)
2. Check the Firebase user is signed in before joining a channel
3. Check the backend server is running and reachable
4. Check the backend `.env` has the correct (newly rotated) certificate
