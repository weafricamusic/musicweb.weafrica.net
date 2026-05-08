Agora token + gift demo server
==============================

Quick start (demo):

1. Copy `.env.example` to `.env` and set `APP_ID`, `APP_CERT`, and `DEMO_API_KEY`.

2. Install and run:

```bash
cd server
npm install
npm start
```

3. Client flow (demo):
- Request `/rtc-token` and `/rtm-token` from the server
- Buyer POSTs to `/purchase-gift` with `Authorization: Bearer <DEMO_API_KEY>`
- Server validates, records transaction (in-memory), then attempts to publish a confirmed gift message to the Agora RTM channel via REST (server-push)

Notes:
- This is a demo. Use real authentication and a persistent DB in production.
- Verify Agora RTM REST publish endpoint and request format in Agora docs for your account — the code uses a placeholder endpoint and Basic auth; adjust to your region/account as required.
