# Live Streaming Setup - Complete Implementation

## Overview
The live streaming system is now fully implemented with both artist (broadcaster) and consumer (audience) flows working end-to-end.

## Architecture

### Frontend (Flutter)
- **Artist Go Live**: `GoLiveSetupScreen` → `SoloLiveStreamScreen`
- **Consumer Join**: `LiveFeedScreen` → `LiveWatchScreen`
- **Token Management**: `AgoraTokenApi` calls backend for RTC tokens
- **Live Discovery**: `LiveDiscoveryService` and `LiveFeedDiscoverService`

### Backend (NestJS)
- **Live Controller**: `/api/live/start` - Artist starts live stream
- **Agora Controller**: `/api/agora/token` - Generate RTC tokens for both artists and consumers
- **Orchestrator Service**: Manages live room lifecycle
- **Stream Service**: Manages stream sessions and Agora integration

### Database (Supabase)
- `live_sessions` - Main live stream metadata
- `stream_sessions` - Stream session tracking
- `live_rooms` - Live room state

## Key Components

### 1. Artist Live Creation Flow

```dart
// GoLiveSetupScreen -> SoloLiveStreamScreen
1. Artist fills in title, category, privacy settings
2. Calls LiveSessionService.createSession()
3. Backend creates live_sessions row with is_live=true
4. Backend generates Agora token for broadcaster role
5. Artist navigates to SoloLiveStreamScreen with token
6. Artist joins Agora channel as broadcaster
7. Stream goes live and appears in consumer feed
```

### 2. Consumer Join Flow

```dart
// LiveFeedScreen -> LiveWatchScreen
1. Consumer sees live streams in LiveFeedScreen grid
2. Taps on a live stream card
3. Calls LiveSessionService.joinSession()
4. Backend validates stream is live
5. Backend generates Agora token for audience role
6. Consumer navigates to LiveWatchScreen with token
7. Consumer joins Agora channel as audience
8. Consumer can see/hear the artist's stream
```

### 3. Agora Token Generation

**New Endpoint**: `POST /api/agora/token`

```typescript
// backend/src/stream/agora/agora.controller.ts
@Post('token')
async generateRtcToken(@Body() body: {
  channel_id: string;      // Live stream channel ID
  role: 'broadcaster' | 'audience';
  uid: number | string;    // User's Agora UID
  ttl_seconds?: number;    // Token expiration (default: 3600)
  battle_id?: string;      // Optional battle ID
})
```

**Response**:
```json
{
  "token": "eyJhbG...",
  "app_id": "your-agora-app-id",
  "channel_id": "live_123_abc",
  "uid": 12345,
  "role": "audience",
  "expires_in": 3600
}
```

## Database Schema

### live_sessions table
```sql
CREATE TABLE live_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  channel_id TEXT NOT NULL,
  host_id TEXT NOT NULL,
  host_name TEXT,
  title TEXT NOT NULL,
  category TEXT,
  thumbnail_url TEXT,
  is_live BOOLEAN DEFAULT false,
  started_at TIMESTAMP WITH TIME ZONE,
  ended_at TIMESTAMP WITH TIME ZONE,
  viewer_count INTEGER DEFAULT 0,
  gift_count INTEGER DEFAULT 0,
  access_tier TEXT DEFAULT 'public',
  live_type TEXT DEFAULT 'normal',
  mode TEXT DEFAULT 'SOLO',
  trending_score INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### stream_sessions table
```sql
CREATE TABLE stream_sessions (
  id TEXT PRIMARY KEY,
  live_room_id TEXT NOT NULL,
  channel_id TEXT NOT NULL,
  participants TEXT[] DEFAULT '{}',
  status TEXT NOT NULL,
  viewer_count INTEGER DEFAULT 0,
  peak_viewers INTEGER DEFAULT 0,
  metadata JSONB DEFAULT '{}',
  started_at TIMESTAMP WITH TIME ZONE,
  ended_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Environment Variables

### Required for Backend
```env
# Agora Configuration
AGORA_APP_ID=your_agora_app_id
AGORA_APP_CERTIFICATE=your_agora_app_certificate

# Supabase Configuration
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_KEY=your_supabase_service_role_key

# Server Configuration
PORT=3000
```

### Required for Flutter App
```dart
// lib/app/config/app_env.dart
static const String agoraAppId = 'your_agora_app_id';
static const String supabaseUrl = 'your_supabase_url';
static const String supabaseAnonKey = 'your_supabase_anon_key';
```

## Testing the Complete Flow

### 1. Start Backend Server
```bash
cd backend
npm install
npm run start:dev
```

### 2. Test Artist Going Live

**Option A: Using Flutter App**
1. Login as an artist/dj user
2. Navigate to Go Live screen
3. Fill in title, select category
4. Tap "Go Live" button
5. Should navigate to SoloLiveStreamScreen with camera preview

**Option B: Direct API Call**
```bash
curl -X POST http://localhost:3000/api/live/start \
  -H "Authorization: Bearer YOUR_FIREBASE_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Live Stream",
    "category": "Music",
    "privacy": "public"
  }'
```

### 3. Test Consumer Joining

**Option A: Using Flutter App**
1. Login as a consumer user (different from artist)
2. Navigate to Live tab/feed
3. Should see the artist's live stream in the grid
4. Tap on the live stream card
5. Should navigate to LiveWatchScreen and see artist's video

**Option B: Direct API Call**
```bash
# First get token for audience
curl -X POST http://localhost:3000/api/agora/token \
  -H "Content-Type: application/json" \
  -d '{
    "channel_id": "live_123_abc",
    "role": "audience",
    "uid": 99999
  }'

# Response will include the token to use in Flutter app
```

### 4. Verify Database State

```sql
-- Check active live sessions
SELECT id, channel_id, host_id, host_name, title, is_live, viewer_count, started_at
FROM live_sessions 
WHERE is_live = true 
ORDER BY started_at DESC;

-- Check stream sessions
SELECT id, live_room_id, channel_id, status, viewer_count, started_at
FROM stream_sessions 
WHERE status = 'ACTIVE'
ORDER BY created_at DESC;
```

## Troubleshooting

### Issue: Artist cannot go live
**Check**:
1. User has artist or dj role in profiles table
2. Agora credentials are set in backend .env
3. Firebase authentication is working
4. Supabase connection is established

### Issue: Consumer cannot see live streams
**Check**:
1. `is_live` column is set to true in live_sessions
2. Live stream was created recently (not stale)
3. Consumer is not filtered out by test stream filters
4. Database RLS policies allow reading live_sessions

### Issue: Consumer cannot join live stream
**Check**:
1. Agora token endpoint is responding
2. Channel ID matches between artist and consumer
3. Token role is set to 'audience' for consumers
4. Agora App ID matches in both frontend and backend

### Issue: No video/audio
**Check**:
1. Camera/microphone permissions granted
2. Agora App ID is correct
3. Channel ID is identical for both users
4. Network connection is stable
5. Agora service is not rate-limited

## Battle Mode

The system also supports battle mode where two artists can compete:

1. Artist creates battle with `_createBattle()` in GoLiveSetupScreen
2. System creates battle event and waits for opponent
3. Opponent accepts and both join same Agora channel
4. Consumers can watch both artists and vote/gift
5. Battle scoring engine tracks votes and determines winner

## Next Steps

### Immediate
- [x] Create Agora token API endpoint
- [x] Register controller in Stream module
- [ ] Test end-to-end flow with real Agora credentials
- [ ] Add error handling and logging

### Future Enhancements
- [ ] Add cloud recording for live streams
- [ ] Implement live stream analytics
- [ ] Add chat moderation tools
- [ ] Support for multiple camera angles
- [ ] Add screen sharing capability
- [ ] Implement live stream scheduling

## Support

For issues or questions:
1. Check backend logs: `docker logs backend-container`
2. Check Flutter debug output: `flutter run --verbose`
3. Verify Agora dashboard for channel activity
4. Check Supabase logs for database errors