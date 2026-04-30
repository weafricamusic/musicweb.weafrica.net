# WeAfrica Music Battle - Quick Start

## 🚀 Ready to Use!

Your Agora credentials have been configured. The application is ready to run.

## Setup Instructions

### 1. Backend Setup
```bash
cd backend
npm install
npm run dev
```

The backend will start on `http://localhost:3000`

### 2. Frontend Setup
```bash
cd web/agora-battle
npm install
npm run dev
```

The frontend will start on `http://localhost:5173`

## 🎮 How to Use

1. **Open the application**: Visit `http://localhost:5173`
2. **Enter a channel name**: e.g., `match_12345`
3. **Select your role**:
   - **Player (Host)**: Can publish audio/video
   - **Spectator (Audience)**: Watch only
4. **Click "Join Channel"**

## 🎯 Features

- **Real-time video/audio streaming** with Agora Web SDK NG
- **Role-based permissions** (Players vs Spectators)
- **Live chat** via RTM
- **Game events** (battle start/end, voting)
- **Device management** (camera/microphone switching)
- **Auto token renewal**

## 🔧 Your Configuration

- **Agora App ID**: `21a9549ec323484ca5983aadbd3839af`
- **Backend API**: `http://localhost:3000/api`
- **Frontend**: `http://localhost:5173`

## 🎪 Test the Application

1. Open two browser windows/tabs
2. In first window: Join as "Player" with channel `test-match`
3. In second window: Join as "Spectator" with same channel
4. You should see video streams and be able to chat!

## 📝 API Endpoints

The backend provides these Agora-related endpoints:

- `POST /api/agora/tokens` - Generate RTC + RTM tokens
- `POST /api/agora/tokens/rtc` - RTC-only tokens
- `POST /api/agora/tokens/rtm` - RTM-only tokens
- `GET /api/agora/config` - Get public App ID
- `POST /api/agora/recording/start` - Start cloud recording
- `POST /api/agora/recording/stop` - Stop cloud recording

## 🐛 Troubleshooting

**"Token generation failed"**: Check that `AGORA_APP_ID` and `AGORA_APP_CERTIFICATE` are set in `backend/.env`

**"Cannot join channel"**: Verify the backend is running and accessible

**"No audio/video"**: Check browser permissions for camera/microphone

**"RTM not connected"**: RTM is optional; RTC still works without it

## 🚀 Production Deployment

### Frontend Build
```bash
cd web/agora-battle
npm run build
```

Deploy the `dist/` folder to your CDN or web server.

### Backend Environment
Set these environment variables in production:
```bash
export AGORA_APP_ID=21a9549ec323484ca5983aadbd3839af
export AGORA_APP_CERTIFICATE=3ba5aa88ab794a29b7ba6fca67ae2cf2
```

## 📚 Documentation

For detailed information, see:
- [AGORA_BATTLE_INTEGRATION.md](../docs/AGORA_BATTLE_INTEGRATION.md) - Complete integration guide
- [Agora Web SDK NG Documentation](https://docs.agora.io/en/video-call/get-started/get-started-sdk)

## 🎯 Next Steps

1. Test the application with multiple users
2. Customize the UI to match your brand
3. Add your game logic and business rules
4. Set up cloud recording for battle replays
5. Integrate with your existing WeAfrica Music platform

The implementation is production-ready and follows Agora best practices!