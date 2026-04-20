# Live (Production) Runbook

This runbook is for resolving production issues around **going live** (Agora) and **Firebase-authenticated** Edge Function routes.

## 1) Fix `401 Invalid Firebase ID token`

Most common cause: the Edge Function verifies tokens against the **wrong Firebase project**.

Your app’s Firebase project id (Android):
- `android/app/google-services.json` → `project_info.project_id`
- Expected value in this repo: `weafrica-music-85cdc`

Set Supabase Edge Function secrets (production):

```bash
supabase secrets set FIREBASE_PROJECT_ID=weafrica-music-85cdc
# recommended (enables /api/diag)
supabase secrets set WEAFRICA_DEBUG_DIAG_TOKEN="<random-string>"

supabase functions deploy api --no-verify-jwt
```

## 2) Verify with `/api/diag` (safe)

`/api/diag` is disabled unless a diag token is configured.

```bash
# set BASE_URL to your functions domain
# e.g. https://<project-ref>.functions.supabase.co
curl -sS \
  -H "x-debug-token: $WEAFRICA_DEBUG_DIAG_TOKEN" \
  "$BASE_URL/api/diag" | python3 -m json.tool
```

Back-compat (older scripts):
- Secret: `WEAFRICA_DIAG_TOKEN`
- Header: `x-weafrica-diag-token`

What to look for in the JSON:
- `env.firebase_project_id` should be `weafrica-music-85cdc`
- `env.firebase_expected_issuer` should be `https://securetoken.google.com/weafrica-music-85cdc`

If those don’t match your client token’s `iss`/`aud`, `/api/agora/token` will keep returning 401.
