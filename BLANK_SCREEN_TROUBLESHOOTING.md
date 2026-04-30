# White Blank Screen - Troubleshooting Guide

## Quick Fixes

### 1. Test with Simple Debug Page
First, test if Flutter is working at all by temporarily replacing your main.dart:

```dart
// In lib/main.dart, replace everything with:
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'If you see this, Flutter works!',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
    ),
  ));
}
```

If you see the text, Flutter is working. If you still see a blank screen, the issue is with your Flutter setup or build.

### 2. Common Causes & Solutions

#### A. Missing Environment Configuration
**Symptom**: App crashes during initialization without visible error

**Solution**: Ensure your `assets/config/supabase.env.json` has valid values:
```json
{
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key",
  "FIREBASE_WEB_API_KEY": "your-firebase-api-key",
  "FIREBASE_WEB_PROJECT_ID": "your-project-id",
  "FIREBASE_WEB_MESSAGING_SENDER_ID": "your-sender-id",
  "FIREBASE_WEB_APP_ID": "your-app-id"
}
```

#### B. Firebase Configuration Issues (Web)
**Symptom**: App fails to initialize Firebase

**Solution**: Check `web/index.html` has correct Firebase config:
```html
<script>
  const firebaseConfig = {
    apiKey: "AIzaSyBy7DgF8Vk39ek75gO7iIi_f8spwDJbgLY",
    authDomain: "weafrica-music-85cdc.firebaseapp.com",
    projectId: "weafrica-music-85cdc",
    messagingSenderId: "985705961084",
    appId: "1:985705961084:web:b494fce32e4a41b8c45bf9"
  };
  firebase.initializeApp(firebaseConfig);
</script>
```

#### C. Audio Service Initialization Failure
**Symptom**: App crashes on startup with audio-related errors

**Solution**: The app now has error handling for audio initialization. Check console for:
```
Audio initialization failed: [error message]
```

If you see this, the app should continue but without audio functionality.

#### D. Supabase Connection Issues
**Symptom**: App stuck on splash screen or shows setup error

**Solution**: 
1. Verify Supabase project is running
2. Check network connectivity
3. Ensure Supabase URL and anon key are correct
4. Check Supabase dashboard for any service interruptions

### 3. Debugging Steps

#### Step 1: Check Console Logs
Run your app and check the browser console (F12) or terminal for errors.

#### Step 2: Enable Debug Mode
Run with debug flags:
```bash
flutter run --debug
# or for web
flutter run -d chrome --web-renderer canvaskit
```

#### Step 3: Check Network Tab
Open browser DevTools > Network tab and look for failed requests to:
- Supabase API
- Firebase services
- Your backend API

#### Step 4: Verify Dependencies
Run:
```bash
flutter pub get
flutter pub upgrade
```

#### Step 5: Clean Build
```bash
flutter clean
flutter pub get
flutter run
```

### 4. Platform-Specific Issues

#### Web
- Ensure you're using a modern browser (Chrome, Firefox, Edge)
- Check if service workers are enabled
- Disable browser extensions that might interfere
- Try incognito/private mode

#### Mobile (Android/iOS)
- Ensure you have a device/emulator connected
- Check if you have the necessary permissions
- Verify Firebase and Supabase are configured for mobile

### 5. Error Recovery

If the app shows a setup error screen (Supabase/Firebase setup screen), it means:
1. The app detected a configuration issue
2. The error message should tell you what's wrong
3. Fix the configuration and restart

### 6. Last Resort

If nothing works, try this minimal test:

1. Create a new Flutter project:
```bash
flutter create test_app
cd test_app
flutter run
```

2. If the test app works, the issue is specific to your project configuration.

3. If the test app also shows a blank screen, there's an issue with your Flutter installation or system.

## Modified Code

I've made the following changes to help with debugging:

### lib/main.dart
- Added try-catch around audio initialization
- Audio failures are now logged but don't crash the app

### lib/app/bootstrap/bootstrap_app.dart
- Added try-catch around WidgetsFlutterBinding.ensureInitialized()
- Better error logging throughout

### lib/simple_debug_page.dart
- New file for quick testing
- Bypasses all initialization
- Shows if Flutter is working at all

## Next Steps

1. Try the simple debug page first
2. Check browser console for errors
3. Verify your configuration files
4. If you find specific errors, search for them in this guide

If you're still stuck, provide:
- Browser console logs
- Terminal output
- Screenshot of the blank screen
- Any error messages you see