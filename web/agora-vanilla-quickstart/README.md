# Agora Web Vanilla Quickstart — Live Streaming + Token Server

Minimal, working example of **Agora Web RTC** in **live mode** with a **Node.js token server**.  
All credentials come from **environment variables** on the server only. The client fetches temporary tokens.

---

## Files

| File | Purpose |
|------|---------|
| `token-server.js` | Express server that generates RTC tokens using `agora-access-token` |
| `index.html` | Vanilla HTML/JS page that joins a channel, publishes/subscribes, and demonstrates host/audience role switching |
| `package.json` | Dependencies |
| `.env.example` | Template for server environment variables |

---

## Prerequisites

1. **Agora account** — sign up at [console.agora.io](https://console.agora.io)
2. **Node.js 16+**
3. A modern browser with camera/microphone access

---

## Setup

### 1. Install dependencies

```bash
cd web/agora-vanilla-quickstart
npm install
```

### 2. Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` and paste your **App ID** and **App Certificate** from the Agora console:

```env
AGORA_APP_ID=21a9549ec323484ca5983aadbd3839af
AGORA_APP_CERTIFICATE=your_actual_certificate_here
PORT=3000
```

> **NEVER commit `.env` or your App Certificate.** It is already ignored by `.gitignore`.

### 3. Start the token server

```bash
npm run server
# or: node token-server.js
```

You should see:

```
Token server running on port 3000
GET  http://localhost:3000/rtc/:channel/:uid/:role
POST http://localhost:3000/token
```

### 4. Serve the HTML page (must be over `http://`, not `file://`)

Option A — `serve` (installed as devDependency):

```bash
npm run open
# or: npx serve . -p 5500
```

Option B — Python:

```bash
python3 -m http.server 5500
```

Option C — VS Code “Live Server” extension.

Open **http://localhost:5500** in your browser.

---

## How to test

1. Open the page in **two browser tabs**.
2. **Tab 1** — enter channel `battleDemo`, pick **host**, click **Join**.  
   Allow camera/mic when prompted.
3. **Tab 2** — enter the **same channel**, pick **audience**, click **Join**.
4. **Verify** — the audience tab should see the host’s video. The host tab can also see its own local preview.
5. **Switch Role** — in the audience tab, click **Switch Role** to become a host. It will fetch a new publisher token, create local tracks, and publish. Now both tabs are hosts in a battle-like setup.

---

## How it works

### Token Server (`token-server.js`)

- Reads `AGORA_APP_ID` and `AGORA_APP_CERTIFICATE` from `.env`.
- Exposes two endpoints:
  - `GET /rtc/:channel/:uid/:role` — quick endpoint used by the HTML page (`role` = `publisher` or `subscriber`).
  - `POST /token` — flexible JSON endpoint for programmatic use.
- Returns a plain token string (GET) or a JSON object (POST).
- Exits immediately if credentials are missing.

### Client (`index.html`)

- Loads the **Agora Web SDK NG** (`AgoraRTC_N-4.24.3.js`) from CDN.
- Has a defensive check: if the SDK fails to load, it shows a red banner.
- On **Join**:
  1. Creates `AgoraRTC.createClient({ mode: 'live', codec: 'vp8' })`.
  2. Fetches a token from the server.
  3. Sets up `user-published` / `user-unpublished` handlers **before** `client.join()`.
  4. Calls `client.join(appId, channel, token, uid)`.
  5. If **host**, creates microphone + camera tracks and `client.publish()` them.
- On **Leave**: stops/closes local tracks, calls `client.leave()`, wipes UI.
- On **Switch Role**:
  - Fetches a new token with the opposite privilege.
  - Calls `client.setClientRole()`.
  - Either creates and publishes tracks (host) or unpublishes and destroys them (audience).
- On page unload: cleans everything up so camera/mic are released.

---

## Architecture Notes

| Component | Responsibility |
|-----------|--------------|
| **Token server** | Holds the App Certificate securely; decides who can publish vs subscribe |
| **Browser client** | Knows the App ID (safe to expose) and its own UID; fetches token from server |
| **Agora Cloud** | Routes audio/video between publishers and subscribers in the channel |

Tokens expire in **1 hour** by default (configurable in `token-server.js`).

---

## Security Checklist

- [ ] App Certificate is **only** in the server environment variables
- [ ] `.env` is in `.gitignore`
- [ ] Token server runs over **HTTPS** in production (use a reverse proxy like Nginx or Caddy)
- [ ] Token endpoint is **authenticated** in production (e.g., require a Firebase/Supabase auth header)
- [ ] Short token TTL (≤ 24 hours, ideally ≤ 1 hour)
- [ ] Rate-limit the token endpoint
- [ ] Validate `channelName` against your database before issuing tokens
- [ ] CORS is restricted to your domain in production (currently `*` for local demo)

---

## Troubleshooting

### “Token server returned 500”
- Check that `.env` exists and has both `AGORA_APP_ID` and `AGORA_APP_CERTIFICATE`.
- Make sure the server is running on the expected port.

### “Cannot join channel / NO_PUBL Permission”
- The server must issue a **publisher** token for hosts and a **subscriber** token for audience.
- Verify `GET /rtc/:channel/:uid/publisher` returns a long token string.

### “No video / black screen”
- Ensure you are serving the page over **HTTP** (`localhost`), not `file://`.
- Check browser console for Agora error codes.
- Allow camera/microphone permissions when prompted.

### “Agora SDK failed to load”
- Check your internet connection — the CDN script must load.
- If your region blocks the CDN, host the SDK file locally.

---

## Next Steps

- Add **chat / gifts / votes** via Agora RTM or a separate WebSocket server.
- Integrate with your backend user database so tokens are tied to authenticated users.
- Deploy the token server to a cloud VM or Vercel/Render.
- Add Cloud Recording to save streams for replay.

---

## Useful Links

- [Agora Web SDK NG docs](https://docs.agora.io/en/video-calling/get-started/get-started-sdk?platform=web)
- [Token authentication guide](https://docs.agora.io/en/video-calling/token-authentication/authentication-workflow)
- [Agora Console](https://console.agora.io)