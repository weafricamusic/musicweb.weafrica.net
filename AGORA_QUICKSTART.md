# Agora Live Streaming - Quick Start Guide

## ✅ What's Already Set Up

Your WeAfrica Music platform has a **complete Agora live streaming system**:

### Backend (NestJS)
- ✅ Token generation API (`/api/agora/token`)
- ✅ RTM token generation (`/api/agora/rtm/token`)
- ✅ Agora packages installed (`agora-token`, `agora-access-token`)
- ✅ Environment configuration files created

### Web Client
- ✅ Agora RTC SDK v4.24.3 integrated
- ✅ Agora RTM SDK v1.4.3 integrated
- ✅ Host (Player) and Audience (Spectator) roles
- ✅ Video/audio publishing and subscribing
- ✅ Real-time chat and game events
- ✅ Battle mode with voting

### Flutter Mobile App
- ✅ Agora RTC engine integrated
- ✅ Live streaming screens for hosts and viewers
- ✅ Battle mode support
- ✅ Device controls (camera, mic, switch)

## 🚀 Quick Start (3 Steps)

### Step 1: Get Your Agora App Certificate

1. Go to [Agora Console](https://console.agora.io)
2. Sign in or create an account
3. Find your project with App ID: `21a9549ec323484ca5983aadbd3839af`
4. Copy the **App Certificate**

### Step 2: Update Backend Configuration

Edit `backend/.env` and replace the placeholder:

```env
# Change this line:
AGORA_APP_CERTIFICATE=your_agora_app_certificate_here

# To:
AGORA_APP_CERTIFICATE=paste_your_actual_certificate_here
```

### Step 3: Test the System

```bash
# 1. Start the backend
cd backend
npm install  # if not already done
npm run dev

# 2. In another terminal, start the web client
cd web/agora-battle
npm install  # if not already done
npm run dev

# 3. Open browser to http://localhost:5173
```

## 📋 Testing Checklist

### Test Token Generation
```bash
# Run the test script
cd backend
node test-agora-token.js

# Or test the API endpoint
curl -X POST http://localhost:3000/api/agora/token \
  -H "Content-Type: application/json" \
  -d '{"channel_id":"test","role":"broadcaster","uid":123}'
```

### Test Live Streaming

1. **Open two browser windows** to `http://localhost:5173`
2. **Window 1**: Enter channel name `test_123`, select **Player (Host)**, click Join
3. **Window 2**: Enter same channel `test_123`, select **Player (Host)**, click Join
4. **Verify**: Both windows should see each other's video
5. **Test chat**: Type messages in the chat box
6. **Test battle**: Use browser console to run `startBattle()`, `endBattle()`

### Test Roles

- **Host (Player)**: Can publish video/audio, controls shown
- **Spectator**: Can only watch, no video controls

## 🔧 Configuration Files

### Backend: `backend/.env`
```env
AGORA_APP_ID=21a9549ec323484ca5983aadbd3839af
AGORA_APP_CERTIFICATE=your_actual_certificate_here
AGORA_TOKEN_EXPIRATION=86400
SUPABASE_URL=https://nxkutpjdoidfwpkjbwcm.supabase.co
SUPABASE_KEY=your_supabase_service_role_key
PORT=3000
```

### Web Client: `web/agora-battle/.env`
```env
VITE_AGORA_APP_ID=21a9549ec323484ca5983aadbd3839af
VITE_API_URL=http://localhost:3000/api
```

## 📱 Mobile App

The Flutter mobile app uses the same Agora App ID:
- Configured in `lib/app/config/app_env.dart`
- Service in `lib/data/services/agora_service.dart`
- Providers in `lib/features/live/providers/agora_provider.dart`

## 🆘 Troubleshooting

### "Token generation failed"
- Check `AGORA_APP_CERTIFICATE` is correct (no extra spaces)
- Ensure backend is running on port 3000
- Run `node test-agora-token.js` to validate

### "Cannot join channel"
- Verify App ID matches in all config files
- Check browser console for errors
- Allow camera/microphone permissions

### "No video/audio"
- Check browser permissions (camera/mic)
- Try a different browser
- Verify devices are not in use by another app

### Backend won't start
- Ensure all dependencies installed: `npm install`
- Check port 3000 is not in use
- Verify Supabase credentials in `.env`

## 📚 Documentation

- **Full Setup Guide**: `AGORA_SETUP_GUIDE.md`
- **Battle Integration**: `docs/AGORA_BATTLE_INTEGRATION.md`
- **Live Experience**: `docs/LIVE_EXPERIENCE_BLUEPRINT.md`

## 🎯 Next Steps

1. **Replace App Certificate** in `backend/.env`
2. **Start backend**: `cd backend && npm run dev`
3. **Start web client**: `cd web/agora-battle && npm run dev`
4. **Test live streaming** in browser
5. **Deploy to production** when ready

## 🔗 Useful Links

- [Agora Console](https://console.agora.io)
- [Agora Documentation](https://docs.agora.io)
- [WeAfrica Music Platform](https://weafrica-music-85cdc.firebaseapp.com)