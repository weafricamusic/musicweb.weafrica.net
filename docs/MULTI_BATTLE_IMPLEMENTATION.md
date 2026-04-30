# Multi-Battle System Implementation Guide

## Overview

This guide covers the complete implementation of a multi-battle system using Agora RTC/RTM for real-time communication, supporting multiple simultaneous battles with Flutter app + Flutter web.

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Multi-Battle Architecture                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │  Flutter     │    │  Flutter     │    │  Web Client  │    │  Admin    │ │
│  │  Mobile App  │    │  Web App     │    │  (Vite + JS) │    │  Dashboard│ │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └─────┬─────┘ │
│         │                    │                    │                   │       │
│         └────────────────────┴────────────────────┴───────────────────┘       │
│                                      │                                        │
│                              ┌───────▼───────┐                               │
│                              │  Backend API   │                               │
│                              │  (Node.js)     │                               │
│                              └───────┬───────┘                               │
│                                      │                                        │
│         ┌────────────────────────────┼────────────────────────────┐          │
│         │                            │                            │          │
│  ┌──────▼───────┐    ┌──────────────▼───────┐    ┌──────────────▼───────┐  │
│  │  Supabase    │    │  Agora Cloud        │    │  Redis              │  │
│  │  Database    │    │  (RTC/RTM)          │    │  (Caching/PubSub)   │  │
│  └──────────────┘    └─────────────────────┘    └─────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Agora Channel Strategy

Each battle gets a unique Agora channel:

```
Channel Naming: battle_{battleId}
Example: battle_1234567890

Roles:
- Host A (Challenger): Publisher role, can publish audio/video
- Host B (Challenged): Publisher role, can publish audio/video  
- Audience: Subscriber role, can only watch/listen
- Admin: Can observe and moderate
```

### Battle Lifecycle

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  PENDING │───▶│  LOBBY   │───▶│COUNTDOWN │───▶│   LIVE   │───▶│  VOTING  │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
     │                                                       │
     │                                                       ▼
     │                                                ┌──────────┐
     │                                                │ RESULTS  │
     │                                                └────┬─────┘
     │                                                     │
     ▼                                                     ▼
┌──────────┐                                            ┌──────────┐
│CANCELLED │                                            │  ENDED   │
└──────────┘                                            └──────────┘
```

## Backend Implementation

### File Structure

```
backend/src/
├── api/
│   ├── agora.js          # Agora token generation
│   ├── battles.js        # Battle CRUD operations
│   ├── voting.js         # Voting endpoints (NEW)
│   └── moderation.js     # Admin tools
├── services/
│   ├── battleService.js  # Battle logic
│   └── votingService.js  # Voting logic (NEW)
└── server.js             # Main server file
```

### Key Endpoints

#### Voting API

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/voting/vote` | Cast a vote |
| GET | `/api/voting/battle/:battleId/results` | Get vote counts |
| GET | `/api/voting/battle/:battleId/breakdown` | Get vote breakdown |
| GET | `/api/voting/battle/:battleId/leaderboard` | Get leaderboard |
| GET | `/api/voting/battle/:battleId/finalize` | Finalize votes (admin) |
| DELETE | `/api/voting/battle/:battleId/reset` | Reset votes (admin) |
| POST | `/api/voting/validate` | Validate voting eligibility |

### Database Schema

```sql
-- Battle votes table
CREATE TABLE battle_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  battle_id TEXT NOT NULL,
  voter_id TEXT NOT NULL,
  candidate_id TEXT NOT NULL,
  vote_type TEXT NOT NULL DEFAULT 'regular',
  weight INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(battle_id, voter_id, vote_type) -- One vote per type per user
);

-- Indexes for performance
CREATE INDEX idx_battle_votes_battle ON battle_votes(battle_id);
CREATE INDEX idx_battle_votes_voter ON battle_votes(voter_id);
CREATE INDEX idx_battle_votes_candidate ON battle_votes(candidate_id);
```

## Flutter Implementation

### File Structure

```
lib/features/battle/
├── models/
│   ├── battle.dart           # Battle, BattleParticipant, Vote models
│   └── battle_state.dart     # BattleState enum, events
├── services/
│   ├── agora_service.dart    # Agora RTC/RTM integration
│   └── battle_api_service.dart # API client
├── screens/
│   ├── battle_lobby_screen.dart
│   ├── battle_room_screen.dart
│   ├── audience_room_screen.dart
│   └── voting_screen.dart
├── widgets/
│   ├── video_grid.dart
│   ├── vote_counter.dart
│   ├── battle_timer.dart
│   └── chat_overlay.dart
└── controllers/
    └── battle_controller.dart
```

### Agora Service Usage

```dart
import 'package:weafrica_music/features/battle/services/agora_service.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

// Initialize
await AgoraService().initialize();

// Join battle as host
await AgoraService().joinBattle(
  battleId: 'battle_123',
  channelId: 'battle_123',
  role: ClientRoleType.broadcaster,
  token: rtcToken,
);

// Listen for events
AgoraService().onBattleState.listen((state) {
  // Handle state changes
});

AgoraService().onVote.listen((voteData) {
  // Handle vote updates
});

// Send vote
await AgoraService().sendVote(candidateId, weight);

// Leave battle
await AgoraService().leaveBattle();
```

### Voting API Usage

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

// Cast vote
final response = await Supabase.instance.client
    .from('battle_votes')
    .insert({
      'battle_id': battleId,
      'voter_id': userId,
      'candidate_id': candidateId,
      'vote_type': 'regular',
      'weight': 1,
    });

// Get vote counts
final response = await http.get(
  Uri.parse('$apiUrl/api/voting/battle/$battleId/results?candidateIds=$candidate1,$candidate2'),
);
```

## Web Implementation

### Agora Web Client

The web client (`web/agora-battle/main.js`) provides:

- RTC channel joining with role management
- RTM for chat and game events
- Video rendering for multiple participants
- Real-time vote counting

### Key Functions

```javascript
// Join channel
await handleJoin();

// Send vote
await sendVote(candidateId);

// Send chat message
await sendMessage();

// Leave channel
await handleLeave();
```

## Configuration

### Environment Variables

#### Backend (.env)
```env
# Agora Configuration
AGORA_APP_ID=your_agora_app_id
AGORA_APP_CERTIFICATE=your_agora_app_certificate
AGORA_TOKEN_EXPIRATION=86400

# Supabase
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_KEY=your_supabase_service_key

# Redis
REDIS_URL=redis://localhost:6379
```

#### Flutter (app_config.dart)
```dart
class AppConfig {
  static const String agoraAppId = 'your_agora_app_id';
  static const String apiUrl = 'https://api.weafrica.net';
}
```

#### Web (.env)
```env
VITE_AGORA_APP_ID=your_agora_app_id
VITE_API_URL=https://api.weafrica.net/api
```

## Testing

### Multi-Battle Test Scenarios

1. **Single Battle Test**
   - Create battle
   - Join as host A
   - Join as host B
   - Start battle
   - Cast votes
   - End battle

2. **Multiple Simultaneous Battles**
   - Create 3 battles
   - Join different battles with different users
   - Verify isolation between battles
   - Test vote counting per battle

3. **High Viewer Count**
   - Create battle with 2 hosts
   - Add 100+ audience members
   - Verify performance
   - Test chat and vote functionality

4. **Reconnection Test**
   - Join battle
   - Simulate network loss
   - Verify auto-reconnect
   - Check state recovery

## Production Deployment

### Scaling Considerations

1. **Agora Channels**
   - Each battle = 1 channel
   - Max 12 hosts per channel (recommended)
   - Unlimited audience per channel

2. **Redis**
   - Use Redis Cluster for high availability
   - TTL on vote keys (1 hour)
   - Pub/Sub for real-time updates

3. **Database**
   - Connection pooling
   - Read replicas for vote queries
   - Partition large tables by date

### Monitoring

Key metrics to monitor:
- Active battles count
- Total concurrent users
- Vote throughput
- API response times
- Agora channel quality

## Troubleshooting

### Common Issues

1. **Token Generation Fails**
   - Verify AGORA_APP_ID and AGORA_APP_CERTIFICATE
   - Check environment variables are loaded

2. **Cannot Join Channel**
   - Verify App ID matches between client and server
   - Check network connectivity
   - Verify token is not expired

3. **Vote Not Counted**
   - Check user eligibility
   - Verify battle is in voting state
   - Check Redis connection

4. **Video/Audio Issues**
   - Check browser permissions
   - Verify camera/microphone availability
   - Check Agora SDK version compatibility

## Additional Resources

- [Agora RTC SDK Documentation](https://docs.agora.io/en/video-call/get-started/get-started-sdk)
- [Agora RTM SDK Documentation](https://docs.agora.io/en/real-time-messaging/overview)
- [Agora Flutter SDK](https://pub.dev/packages/agora_rtc_engine)
- [Supabase Documentation](https://supabase.com/docs)