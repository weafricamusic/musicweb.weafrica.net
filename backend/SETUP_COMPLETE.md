# Live Streaming + Challenges (Backend)

This backend already includes:
- Live session orchestration (`OrchestratorModule`)
- Stream session tracking (`StreamModule`)
- Firebase auth guard (`FirebaseAuthGuard`)

This update adds:
- Challenge creation/acceptance (`ChallengeService`)
- Live HTTP endpoints (`LiveController`)
- Live websocket gateway (`LiveGateway`, namespace `live`)

## API Endpoints

### Start solo live
`POST /live/start`
- Auth: `Authorization: Bearer <Firebase ID token>`
- Body: `{ "title"?: string, "category"?: string, "coverImage"?: string, "privacy"?: "public"|"followers" }`
- Returns: `{ streamId, liveRoomId, channelId, token, agoraAppId }`

### Challenge a live user
`POST /live/challenge/:userId`
- Auth: `Authorization: Bearer <Firebase ID token>`
- Body: `{ "message"?: string }`

### Accept a challenge
`POST /live/accept-challenge/:challengeId`
- Auth: `Authorization: Bearer <Firebase ID token>`

### List active live sessions
`GET /live/active`

### List pending challenges
`GET /live/challenges/pending`
- Auth: `Authorization: Bearer <Firebase ID token>`

## WebSocket

Socket.IO namespace: `/live`

Events supported:
- client → server: `identify`, `join-stream`, `leave-stream`
- server → client: `viewer-count`, `new-stream`, `stream-ended`, `new-challenge`, `battle-starting`

## Supabase

Migration added (run via Supabase migrations):
- `supabase/migrations/20260327120000_stream_challenges.sql`

## Environment variables

Backend expects (see `backend/src/common/supabase/supabase.service.ts` and Agora token service):
- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`
- `AGORA_APP_ID`
- `AGORA_APP_CERTIFICATE`

## Build

From repo root:
- `npm --prefix backend run build:nest`
