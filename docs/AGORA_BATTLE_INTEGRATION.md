# WeAfrica Music Battle - Agora RTC/RTM Integration Guide

## Overview

This guide covers the complete integration of Agora Web SDK NG for real-time interactive battles with players and spectators in the WeAfrica Music platform.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Web Client    │────▶│  Backend API    │────▶│   Agora Cloud   │
│  (Vite + JS)    │◀────│  (Node.js)      │◀────│   (RTC/RTM)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │    Token Request      │                       │
        │──────────────────────▶│                       │
        │                       │    Generate Token     │
        │                       │──────────────────────▶│
        │                       │                       │
        │    Return Tokens      │                       │
        │◀──────────────────────│                       │
        │                       │                       │
        │         Join Channel with Token               │
        │──────────────────────────────────────────────▶│
        │                       │                       │
        │         Audio/Video Streams (P2P/Mesh)        │
        │◀─────────────────────────────────────────────▶│
```

## Components

### 1. Web Client (`web/agora-battle/`)

- **index.html**: Main UI with video containers, controls, and chat
- **main.js**: Agora RTC/RTM client logic
- **vite.config.js**: Build configuration
- **package.json**: Dependencies

### 2. Backend API (`backend/src/api/agora.js`)

Token generation endpoints:
- `POST /api/agora/tokens` - Generate RTC + RTM tokens
- `POST /api/agora/tokens/rtc` - Generate RTC-only token
- `POST /api/agora/tokens/rtm` - Generate RTM-only token
- `GET /api/agora/config` - Get public App ID
- `POST /api/agora/recording/start` - Start cloud recording
- `POST /api/agora/recording/stop` - Stop cloud recording

## Setup Instructions

### Prerequisites

1. **Agora Account**: Sign up at [console.agora.io](https://console.agora.io)
2. **Create a Project**: Get your App ID and App Certificate
3. **Node.js**: v16+ for backend, v18+ for frontend

### Backend Configuration

1. Add environment variables to your backend `.env` file:

```env
# Agora Configuration
AGORA_APP_ID=your_agora_app_id_here
AGORA_APP_CERTIFICATE=your_agora_app_certificate_here
AGORA_TOKEN_EXPIRATION=86400
```

2. Install dependencies (already installed in package.json):

```bash
cd backend
npm install agora-token
```

3. Restart the backend server:

```bash
npm run dev
```

### Frontend Configuration

1. Copy the example environment file:

```bash
cd web/agora-battle
cp .env.example .env
```

2. Edit `.env` with your values:

```env
VITE_AGORA_APP_ID=your_agora_app_id_here
VITE_API_URL=http://localhost:3000/api
```

3. Install dependencies:

```bash
npm install
```

4. Start the development server:

```bash
npm run dev
```

## Usage

### Joining a Channel

1. Open the web app at `http://localhost:5173`
2. Enter a channel name (e.g., `match_12345`)
3. Select your role:
   - **Player (Host)**: Can publish audio/video
   - **Spectator (Audience)**: Subscribe only
4. Click "Join Channel"

### Programmatic Usage

```javascript
// Join a channel
await handleJoin();

// Leave a channel
await handleLeave();

// Switch role
setRole('host'); // or 'audience'

// Send chat message
sendMessage();

// Game events
startBattle();
endBattle();
sendVote(candidateId);
```

## API Reference

### Token Generation

**Request:**
```http
POST /api/agora/tokens
Content-Type: application/json

{
  "channelName": "match_12345",
  "role": "host",
  "uid": 12345  // Optional, leave out to auto-generate
}
```

**Response:**
```json
{
  "rtcToken": "006e...",
  "rtmToken": "006e...",
  "appId": "a9ca...",
  "channel": "match_12345",
  "uid": 12345,
  "role": "host",
  "expiresAt": "2024-04-23T17:00:00.000Z"
}
```

## Client Roles

### Host (Player)
- Can publish audio and video
- Can interact with other hosts
- Limited to ~4-12 per channel (recommended)

### Audience (Spectator)
- Subscribe only
- Can watch all hosts
- Unlimited capacity
- Can use RTM for chat

## RTM for Game Events

The RTM (Real-Time Messaging) SDK is used for:
- Chat messages between participants
- Game state synchronization
- Vote casting
- Battle start/end events

### Game Event Types

```javascript
// Battle start
{
  type: 'game-event',
  eventType: 'battle-start',
  data: { startTime: Date.now(), duration: 180000 }
}

// Vote
{
  type: 'game-event',
  eventType: 'vote',
  data: { candidateId: 'user_123', timestamp: Date.now() }
}

// Battle end
{
  type: 'game-event',
  eventType: 'battle-end',
  data: { endTime: Date.now() }
}
```

## Cloud Recording

For recording battles, use the cloud recording endpoints:

```javascript
// Start recording
POST /api/agora/recording/start
{
  "channelName": "match_12345"
}

// Stop recording
POST /api/agora/recording/stop
{
  "channelName": "match_12345",
  "recordingId": "recording_sid"
}
```

## Performance Tips

1. **Limit Publishers**: Keep host count under 12 per channel
2. **Video Quality**: Use 720p/30fps for players
3. **Token Refresh**: Tokens auto-renew on expiration
4. **Network Monitoring**: Use `client.getStats()` for quality metrics

## Security

- Never expose App Certificate to clients
- Always generate tokens server-side
- Use short token TTLs (24 hours recommended)
- Validate user permissions before token generation

## Troubleshooting

### Common Issues

1. **"Token generation failed"**
   - Check AGORA_APP_ID and AGORA_APP_CERTIFICATE are set
   - Verify App Certificate is correct

2. **"Cannot join channel"**
   - Verify App ID matches between client and server
   - Check network connectivity

3. **"No audio/video"**
   - Check browser permissions
   - Verify camera/microphone are available

4. **"RTM not connected"**
   - RTM is optional; RTC still works without it
   - Check RTM token generation

## Production Deployment

### Frontend Build

```bash
cd web/agora-battle
npm run build
```

Deploy the `dist/` folder to your CDN or web server.

### Backend Deployment

Ensure environment variables are set in production:

```bash
export AGORA_APP_ID=your_production_app_id
export AGORA_APP_CERTIFICATE=your_production_app_certificate
```

### CORS Configuration

Update CORS settings in `backend/src/server.js`:

```javascript
const io = new Server(httpServer, {
  cors: {
    origin: ['https://your-domain.com'],
    credentials: true
  }
});
```

## Additional Resources

- [Agora Web SDK NG Documentation](https://docs.agora.io/en/video-call/get-started/get-started-sdk)
- [Agora RTM Documentation](https://docs.agora.io/en/real-time-messaging/overview?platform=web)
- [Agora Cloud Recording](https://docs.agora.io/en/cloud-recording/product-overview?platform=restful)

## Support

For issues specific to:
- **Agora SDK**: Check Agora documentation or support
- **WeAfrica Integration**: Check backend logs and browser console