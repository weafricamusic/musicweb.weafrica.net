#!/bin/bash
# 🔔 PUSH NOTIFICATION SMOKE TEST - QUICK START SCRIPT
# 
# Run this script to verify your push notification setup is working
# Usage: bash run_smoke_test.sh

echo "🔔 PUSH NOTIFICATION SMOKE TEST - QUICK START"
echo "=============================================="
echo ""

# Check if flutter is available
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first."
    exit 1
fi

echo "✅ Flutter found"
echo ""

# Check if firebase CLI is available
if ! command -v firebase &> /dev/null; then
    echo "⚠️  Firebase CLI not found. Install with: npm install -g firebase-tools"
    echo "    (Optional, only needed if deploying Cloud Functions)"
fi

echo ""
echo "📋 PRE-TEST CHECKLIST:"
echo "==================="
echo ""
echo "Before running the smoke test, ensure:"
echo "  ✅ 1. You're logged in to the app (Firebase Auth)"
echo "  ✅ 2. Backend URL updated in push_smoke_test_helper.dart"
echo "  ✅ 3. Supabase table notification_device_tokens exists"
echo "  ✅ 4. Cloud Functions deployed (if new)"
echo ""

read -p "Have you completed all checklist items? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please complete checklist first"
    exit 1
fi

echo ""
echo "🚀 RUNNING SMOKE TEST..."
echo "======================="
echo ""

# Run flutter with verbose logging for debugging
echo "Starting Flutter app with verbose logging..."
echo "(Watch the console output for test results)"
echo ""

flutter run -v

echo ""
echo "📊 NEXT STEPS:"
echo "============="
echo ""
echo "1. ✅ Check the console output above for test results"
echo "2. ✅ Look for '✅ SMOKE TEST PASSED' message"
echo "3. ✅ Verify token appears in Supabase:"
echo "      SELECT * FROM notification_device_tokens"
echo "      WHERE user_id = 'YOUR_FIREBASE_UID'"
echo ""
echo "4. ✅ Test receiving notification:"
echo "      - Go to Admin Dashboard"
echo "      - Send test notification"
echo "      - Watch device for notification"
echo ""
echo "5. ✅ Test rate-limiting:"
echo "      - Run: await PushRateLimitTest().runRateLimitTest()"
echo "      - Expect: First 200 OK, Second 429 Limited"
echo ""
echo "📞 Having issues? See PUSH_SMOKE_TEST_IMPLEMENTATION.md"
