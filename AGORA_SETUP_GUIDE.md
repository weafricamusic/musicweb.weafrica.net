# Agora Live Streaming Setup Guide

This guide covers the complete setup for live streaming on WeAfrica Music platform using Agora SDK.

## Overview

The platform supports:
- **Artists/DJs**: Go live, host battles, stream audio/video
- **Consumers**: Watch live streams, chat, react, send gifts
- **Battle Mode**: Two artists/DJs compete with real-time voting

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Web Client     │     │  Backend API    │     │  Agora Cloud    │
│ (Flutter Web)   │────▶│  (NestJS)       │────▶│  (RTC/RTM)      │
│                 │◀────│                 │◀────│                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Prerequisites

1. **Agora Account**: Sign up at [console.agora.io](https://console.agora.io)
2. **Create a Project**: Get your App ID and App Certificate
3. **Node.js**: v16+ for backend, v18+ for frontend

## Configuration

### 1. Backend Configuration

**File**: `backend/.env`

```env
# Agora Configuration
AGORA_APP_ID=21a9549ec323484ca5983aadbd3839af
AGORA_APP_CERTIFICATE=3ba5aa88ab794a29b7ba6fca67ae2cf2
AGORA_TOKEN_EXPIRATION=86400

# Optional: For Agora REST API (kicking rules, cloud recording)
# AGORA_CUSTOMER_ID=your_customer_id
# AGORA_CUSTOMER_SECRET=your_customer_secret

# Supabase Configuration
SUPABASE_URL=https://nxkutpjdoidfwpkjbwcm.supabase.co
SUPABASE_KEY=your_supabase_service_role_key_here

# Server Configuration
PORT=3000
```

**Important**: Replace `your_agora_app_certificate_here` with your actual App Certificate from Agora console.

### 2. Web Client Configuration

**File**: `web/agora-battle/.env`

```env
VITE_AGORA_APP_ID=21a9549ec323484ca5983aadbd3839af
VITE_API_URL=http://localhost:3000/api
```

For production, update `VITE_API_URL` to your deployed backend URL.

## Installation

### Backend Setup

```bash
cd backend
npm install
npm run dev
```

### Web Client Setup

```bash
cd web/agora-battle
npm install
npm run dev
```

The web client will be available at `http://localhost:5173`

## Testing

### 1. Test Token Generation

```bash
# Test RTC token generation
curl -X POST http://localhost:3000/api/agora/token \
  -H "Content-Type: application/json" \
  -d '{
    "channel_id": "test_channel",
    "role": "broadcaster",
    "uid": 12345,
    "ttl_seconds": 3600
  }'
```

**Expected Response**:
```json
{
  "token": "006e...",
  "app_id": "21a9549ec323484ca5983aadbd3839af",
  "channel_id": "test_channel",
  "uid": 12345,
  "role": "broadcaster",
  "expires_in": 3600
}
```

### 2. Test Web Client

1. Open browser to `http://localhost:5173`
2. Enter a channel name (e.g., `test_123`)
3. Select role: **Player (Host)** or **Spectator**
4. Click **Join Channel**
5. Allow camera/microphone permissions

### 3. Test Battle Mode

1. Open two browser windows
2. Join same channel as **Player (Host)** in both
3. Both should see each other's video
4. Use chat to test RTM messaging
5. Test battle events: `startBattle()`, `endBattle()`, `sendVote(userId)`

## API Reference

### Token Generation Endpoints

#### Generate RTC Token
```http
POST /api/agora/token
Content-Type: application/json

{
  "channel_id": "channel_name",
  "role": "broadcaster" | "audience",
  "uid": 12345,
  "ttl_seconds": 3600,
  "battle_id": "optional_battle_id"
}
```

#### Generate RTM Token
```http
POST /api/agora/rtm/token
Content-Type: application/json

{
  "ttl_seconds": 3600,
  "user_id": "optional_user_id"
}
```

#### Get Config
```http
POST /api/agora/config
```

## Flutter Mobile Integration

The Flutter app uses the same Agora App ID configured in `lib/app/config/app_env.dart`:

```dart
class AppEnv {
  static const String agoraAppId = "21a9549ec323484ca5983aadbd3839af";
}
```

The `AgoraService` in `lib/data/services/agora_service.dart` handles:
- Channel joining/leaving
- Audio/video publishing
- Role management (broadcaster/audience)
- Device switching (camera/mic)

## Troubleshooting

### Common Issues

1. **"Token generation failed"**
   - Check `AGORA_APP_ID` and `AGORA_APP_CERTIFICATE` are correct
   - Ensure backend is running
   - Check backend logs: `backend/logs/`

2. **"Cannot join channel"**
   - Verify App ID matches between client and server
   - Check network connectivity
   - Ensure browser has camera/mic permissions

3. **"No audio/video"**
   - Check browser permissions
   - Verify camera/microphone are available
   - Try switching devices in the UI

4. **"RTM not connected"**
   - RTM is optional; RTC still works without it
   - Check RTM token generation
   - Verify Agora RTM SDK is loaded

### Debug Commands

```bash
# Check backend health
curl http://localhost:3000/api/agora/config

# Test token generation
curl -X POST http://localhost:3000/api/agora/token \
  -H "Content-Type: application/json" \
  -d '{"channel_id":"test","role":"broadcaster","uid":123}'

# View backend logs
tail -f backend/logs/*.log
```

## Production Deployment

### Backend

1. Set environment variables in production
2. Use HTTPS for all API endpoints
3. Configure CORS for your domain
4. Set up monitoring and logging

### Web Client

1. Build for production:
   ```bash
   cd web/agora-battle
   npm run build
   ```
2. Deploy `dist/` folder to CDN or web server
3. Update `VITE_API_URL` to production backend URL

### Security

- Never expose `AGORA_APP_CERTIFICATE` to clients
- Always generate tokens server-side
- Use short token TTLs (24 hours recommended)
- Validate user permissions before token generation
- Use HTTPS in production

## Additional Resources

- [Agora Web SDK NG Documentation](https://docs.agora.io/en/video-call/get-started/get-started-sdk)
- [Agora RTM Documentation](https://docs.agora.io/en/real-time-messaging/overview?platform=web)
- [Agora Cloud Recording](https://docs.agora.io/en/cloud-recording/product-overview?platform=restful)
- [WeAfrica Battle Integration Guide](docs/AGORA_BATTLE_INTEGRATION.md)

## Support

For issues:
- **Agora SDK**: Check [Agora documentation](https://docs.agora.io)
- **WeAfrica Integration**: Check backend logs and browser console
- **Configuration**: Review this guide and `.env` files