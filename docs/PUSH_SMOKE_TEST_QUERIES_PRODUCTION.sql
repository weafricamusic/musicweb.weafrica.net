-- ✅ FINAL — WEAFRICA MUSIC
-- 5-Minute End-to-End Smoke Test (Production-Accurate)
-- 
-- This matches your ACTUAL Next.js + Supabase implementation
-- Run these queries in Supabase SQL Editor after device registration

-- ═══════════════════════════════════════════════════════════════════════════

-- 🔹 STEP 2 — Verify Token Stored in Supabase

-- ✅ CHECK 1: View most recent device registrations
SELECT
  token,
  user_uid,
  topics,
  country_code,
  platform,
  device_id,
  last_seen_at
FROM notification_device_tokens
ORDER BY last_seen_at DESC
LIMIT 20;

-- Expected:
-- • token = Your FCM device token
-- • user_uid = Your Firebase UID
-- • topics = ["all", "consumers"] (JSONB array)
-- • country_code = "mw" or your test country
-- • last_seen_at = Recent timestamp

-- ═══════════════════════════════════════════════════════════════════════════

-- ✅ CHECK 2: Find your specific device token
-- Replace YOUR_FCM_TOKEN with actual token from app
SELECT
  token,
  user_uid,
  topics,
  country_code,
  platform,
  device_id,
  last_seen_at,
  created_at
FROM notification_device_tokens
WHERE token = 'YOUR_FCM_TOKEN'
LIMIT 1;

-- ═══════════════════════════════════════════════════════════════════════════

-- ✅ CHECK 3: Find all tokens for your Firebase UID
-- Replace YOUR_FIREBASE_UID with actual UID
SELECT
  token,
  platform,
  country_code,
  topics,
  last_seen_at
FROM notification_device_tokens
WHERE user_uid = 'YOUR_FIREBASE_UID'
ORDER BY last_seen_at DESC;

-- ═══════════════════════════════════════════════════════════════════════════

-- ✅ CHECK 4: Verify topics are correct (JSONB array)
SELECT
  user_uid,
  topics,
  topics @> '["all"]'::jsonb AS has_all_topic,
  topics @> '["consumers"]'::jsonb AS has_consumers_topic
FROM notification_device_tokens
WHERE user_uid = 'YOUR_FIREBASE_UID';

-- Expected:
-- • has_all_topic = true
-- • has_consumers_topic = true

-- ═══════════════════════════════════════════════════════════════════════════

-- ✅ CHECK 5: Count tokens by country
SELECT
  country_code,
  COUNT(*) AS device_count
FROM notification_device_tokens
GROUP BY country_code
ORDER BY device_count DESC;

-- Expected: Your country_code appears with count >= 1

-- ═══════════════════════════════════════════════════════════════════════════

-- ✅ CHECK 6: Find tokens subscribed to specific topic
SELECT
  user_uid,
  token,
  country_code,
  topics
FROM notification_device_tokens
WHERE topics @> '["consumers"]'::jsonb
ORDER BY last_seen_at DESC
LIMIT 10;

-- ═══════════════════════════════════════════════════════════════════════════

-- ✅ VERIFICATION CHECKLIST

-- After running queries above, verify:
-- ☐ Query 1 shows your token in recent registrations
-- ☐ Query 2 finds your specific token
-- ☐ Query 3 shows all your devices
-- ☐ Query 4 confirms topics are JSONB arrays with correct values
-- ☐ Query 5 shows your country with active devices
-- ☐ Query 6 shows your token in "consumers" topic
-- ☐ user_uid matches your Firebase UID
-- ☐ last_seen_at is recent (within last few minutes)

-- When all checks pass: ✅ SMOKE TEST COMPLETE

-- ═══════════════════════════════════════════════════════════════════════════

-- 🔧 TROUBLESHOOTING

-- Problem: No rows returned
-- Solution: Check Next.js API route is deployed and working

-- Problem: user_uid is null
-- Solution: Verify Firebase ID Token is being sent correctly

-- Problem: topics is not an array
-- Solution: Check Next.js API is sending topics as JSONB array

-- Problem: last_seen_at is old
-- Solution: Device hasn't checked in recently, may need to re-register

-- ═══════════════════════════════════════════════════════════════════════════

-- Version: 1.0 (Production-Accurate)
-- Date: January 28, 2026
-- System: Next.js API + Supabase
-- Status: ✅ Production Ready
