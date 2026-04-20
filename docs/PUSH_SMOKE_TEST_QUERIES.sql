-- 🔍 PUSH NOTIFICATION SMOKE TEST - STEP 3
-- Device Token Verification Queries
-- 
-- Use these queries in the Supabase SQL Editor to verify your device tokens
-- after running the smoke test.
--
-- Location: https://app.supabase.com/project/[PROJECT_ID]/sql/new

-- ✅ QUERY 1: Verify your device token was registered
-- Replace YOUR_FCM_TOKEN with the actual token from the app console
SELECT 
    id,
    user_id,
    fcm_token,
    platform,
    device_model,
    country_code,
    is_active,
    topics,
    created_at,
    last_updated
FROM notification_device_tokens
WHERE fcm_token = 'YOUR_FCM_TOKEN'
LIMIT 1;

-- ✅ QUERY 2: List all active tokens for current user
-- Replace YOUR_USER_ID with the Firebase UID from the app console
SELECT 
    id,
    fcm_token,
    platform,
    device_model,
    country_code,
    is_active,
    topics,
    last_updated
FROM notification_device_tokens
WHERE user_id = 'YOUR_USER_ID'
AND is_active = true
ORDER BY last_updated DESC;

-- ✅ QUERY 3: Check most recently registered tokens (debugging)
-- Shows last 10 tokens registered across all users
SELECT 
    id,
    user_id,
    fcm_token,
    platform,
    device_model,
    country_code,
    is_active,
    last_updated
FROM notification_device_tokens
ORDER BY last_updated DESC
LIMIT 10;

-- ✅ QUERY 4: Count tokens by country (analytics)
SELECT 
    country_code,
    COUNT(*) as token_count,
    COUNT(CASE WHEN is_active = true THEN 1 END) as active_tokens,
    COUNT(CASE WHEN is_active = false THEN 1 END) as inactive_tokens
FROM notification_device_tokens
GROUP BY country_code
ORDER BY token_count DESC;

-- ✅ QUERY 5: Find tokens by platform
SELECT 
    platform,
    COUNT(*) as total,
    COUNT(CASE WHEN is_active = true THEN 1 END) as active,
    COUNT(CASE WHEN device_model IS NOT NULL THEN 1 END) as with_model_info
FROM notification_device_tokens
GROUP BY platform;

-- ✅ QUERY 6: Check for duplicate tokens (should be empty)
SELECT 
    fcm_token,
    COUNT(*) as duplicate_count,
    STRING_AGG(user_id, ', ') as user_ids
FROM notification_device_tokens
GROUP BY fcm_token
HAVING COUNT(*) > 1;

-- ✅ QUERY 7: Tokens that haven't been updated recently (potential stale tokens)
SELECT 
    id,
    user_id,
    fcm_token,
    device_model,
    platform,
    last_updated,
    (NOW() - last_updated) as days_inactive
FROM notification_device_tokens
WHERE is_active = true
AND last_updated < NOW() - INTERVAL '7 days'
ORDER BY last_updated ASC
LIMIT 20;

-- ✅ QUERY 8: Verify notification sending to a specific country
SELECT 
    id,
    user_id,
    fcm_token,
    platform,
    topics,
    is_active
FROM notification_device_tokens
WHERE country_code = 'gh'  -- Change 'gh' to your test country
AND is_active = true
ORDER BY created_at DESC
LIMIT 5;

-- ✅ QUERY 9: Check if user is subscribed to a specific topic
SELECT 
    id,
    user_id,
    topics,
    platform
FROM notification_device_tokens
WHERE user_id = 'YOUR_USER_ID'  -- Replace with Firebase UID
AND topics @> ARRAY['consumers']  -- Check for specific topic
AND is_active = true;

-- ✅ QUERY 10: Device registration timeline (when devices registered)
SELECT 
    DATE(created_at) as registration_date,
    COUNT(*) as devices_registered,
    COUNT(DISTINCT user_id) as unique_users
FROM notification_device_tokens
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY registration_date DESC;

-- 🔧 ADMIN MAINTENANCE QUERIES

-- Clean up inactive tokens older than 30 days
-- ⚠️ CAUTION: Run with backup first
-- DELETE FROM notification_device_tokens
-- WHERE is_active = false
-- AND last_updated < NOW() - INTERVAL '30 days';

-- Deactivate all tokens for a user (logout all devices)
-- ⚠️ CAUTION: This will log out user everywhere
-- UPDATE notification_device_tokens
-- SET is_active = false
-- WHERE user_id = 'YOUR_USER_ID';

-- Reset a specific token to active (recovery)
-- UPDATE notification_device_tokens
-- SET is_active = true, last_updated = NOW()
-- WHERE fcm_token = 'YOUR_FCM_TOKEN';

-- 📊 SMOKE TEST VERIFICATION CHECKLIST
-- 
-- ✅ After running the smoke test, verify:
-- 
-- 1. Query 1 returns exactly 1 row with your token
-- 2. Query 2 shows all active tokens for your user
-- 3. Query 3 shows your token in the most recent list
-- 4. Query 4 shows your country_code with active tokens
-- 5. Query 5 shows your platform with active tokens
-- 6. Query 6 is empty (no duplicate tokens)
-- 7. Query 8 returns your device if you're testing in 'gh'
-- 8. Your token has topics: ['all', 'consumers'] or similar
-- 9. is_active = true for all your tokens
-- 10. last_updated is recent (within last few minutes)
