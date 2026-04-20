// Firebase Cloud Function for device token registration
// Deploy with: firebase deploy --only functions:registerDeviceToken

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { createClient } from "@supabase/supabase-js";

admin.initializeApp();

const supabaseUrl = process.env.SUPABASE_URL || "";
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE || "";
const supabase = createClient(supabaseUrl, supabaseKey);

interface RegisterTokenRequest {
  token: string;
  platform: "ios" | "android";
  device_model?: string;
  country_code?: string;
  topics?: string[];
}

/**
 * 📱 REGISTER DEVICE TOKEN ENDPOINT
 * 
 * Used in STEP 2 of push notification smoke test.
 * 
 * Endpoint: POST /api/push/register
 * Auth: Bearer <Firebase ID Token>
 * 
 * Request body:
 * {
 *   "token": "fcm_device_token",
 *   "platform": "ios" | "android",
 *   "device_model": "iPhone 15",
 *   "country_code": "gh",
 *   "topics": ["all", "consumers"]
 * }
 * 
 * Response (200 OK):
 * {
 *   "success": true,
 *   "message": "Device token registered",
 *   "data": {
 *     "id": "token-uuid",
 *     "user_id": "firebase-uid",
 *     "fcm_token": "token...",
 *     "platform": "ios",
 *     "country_code": "gh",
 *     "is_active": true,
 *     "created_at": "2025-01-28T10:30:00Z",
 *     "last_updated": "2025-01-28T10:30:00Z"
 *   }
 * }
 */
export const registerDeviceToken = functions
  .region("us-east1")
  .https.onRequest(async (req, res) => {
    // CORS handling
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(200).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      // Verify Firebase Auth token
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing or invalid authorization header" });
        return;
      }

      const idToken = authHeader.substring(7);
      let decodedToken;
      try {
        decodedToken = await admin.auth().verifyIdToken(idToken);
      } catch (error) {
        console.error("Token verification failed:", error);
        res.status(401).json({ error: "Invalid token" });
        return;
      }

      const userId = decodedToken.uid;

      // Validate request body
      const {
        token,
        platform,
        device_model,
        country_code,
        topics,
      } = req.body as RegisterTokenRequest;

      if (!token || !platform) {
        res.status(400).json({
          error: "Missing required fields: token, platform",
        });
        return;
      }

      if (!["ios", "android"].includes(platform)) {
        res.status(400).json({
          error: 'Platform must be "ios" or "android"',
        });
        return;
      }

      console.log(`📱 Registering device token for user: ${userId}`);
      console.log(`   Platform: ${platform}`);
      console.log(`   Token: ${token.substring(0, 20)}...`);
      console.log(`   Country: ${country_code || "unknown"}`);

      // Check if token already exists
      const { data: existingToken, error: checkError } = await supabase
        .from("notification_device_tokens")
        .select("id")
        .eq("fcm_token", token)
        .single()
        .then(
          (result) => ({ data: result.data, error: null }),
          (error) => ({ data: null, error })
        );

      // Upsert token (insert or update)
      const now = new Date().toISOString();
      const tokenData = {
        user_id: userId,
        fcm_token: token,
        platform,
        is_active: true,
        country_code: country_code || null,
        app_version: req.body.app_version || null,
        device_model: device_model || null,
        locale: req.body.locale || null,
        topics: topics || ["all"],
        last_updated: now,
        ...(existingToken === null && { created_at: now }),
      };

      const { data: result, error: upsertError } = await supabase
        .from("notification_device_tokens")
        .upsert(tokenData, { onConflict: "fcm_token" })
        .select()
        .single();

      if (upsertError) {
        console.error("Error upserting token:", upsertError);
        res.status(500).json({
          error: "Failed to register token",
          details: upsertError.message,
        });
        return;
      }

      console.log(`✅ Device token registered: ${result.id}`);

      // Subscribe to topics (optional)
      if (topics && topics.length > 0) {
        try {
          for (const topic of topics) {
            await admin.messaging().subscribeToTopic([token], topic);
            console.log(`✅ Subscribed to topic: ${topic}`);
          }
        } catch (error) {
          console.warn("Warning: Failed to subscribe to topics:", error);
          // Don't fail the whole request if topic subscription fails
        }
      }

      // Return success response
      res.status(200).json({
        success: true,
        message: existingToken ? "Device token updated" : "Device token registered",
        data: result,
      });
    } catch (error) {
      console.error("Error in registerDeviceToken:", error);
      res.status(500).json({
        error: "Internal server error",
        details: error instanceof Error ? error.message : String(error),
      });
    }
  });

/**
 * ✅ VERIFY DEVICE TOKEN STATUS
 * 
 * GET /api/push/verify/:fcmToken
 * Auth: Bearer <Firebase ID Token>
 * 
 * Returns token details from Supabase
 */
export const verifyDeviceToken = functions
  .region("us-east1")
  .https.onRequest(async (req, res) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "GET, OPTIONS");

    if (req.method === "OPTIONS") {
      res.status(200).send("");
      return;
    }

    if (req.method !== "GET") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      // Extract token from URL
      const tokenPath = req.path.split("/").pop();
      if (!tokenPath) {
        res.status(400).json({ error: "Missing token parameter" });
        return;
      }

      const { data: token, error } = await supabase
        .from("notification_device_tokens")
        .select("*")
        .eq("fcm_token", tokenPath)
        .single();

      if (error || !token) {
        res.status(404).json({ error: "Token not found" });
        return;
      }

      res.status(200).json({
        success: true,
        data: token,
      });
    } catch (error) {
      console.error("Error in verifyDeviceToken:", error);
      res.status(500).json({
        error: "Internal server error",
        details: error instanceof Error ? error.message : String(error),
      });
    }
  });

/**
 * 🗑️ DEREGISTER DEVICE TOKEN
 * 
 * POST /api/push/deregister
 * Auth: Bearer <Firebase ID Token>
 * 
 * Body: { "token": "fcm_token" }
 * 
 * Used during logout or app uninstall
 */
export const deregisterDeviceToken = functions
  .region("us-east1")
  .https.onRequest(async (req, res) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "POST, OPTIONS");

    if (req.method === "OPTIONS") {
      res.status(200).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing authorization" });
        return;
      }

      const idToken = authHeader.substring(7);
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      const userId = decodedToken.uid;

      const { token } = req.body;
      if (!token) {
        res.status(400).json({ error: "Missing token" });
        return;
      }

      // Deactivate token
      const { error } = await supabase
        .from("notification_device_tokens")
        .update({ is_active: false })
        .eq("fcm_token", token)
        .eq("user_id", userId);

      if (error) {
        throw error;
      }

      // Unsubscribe from all topics
      try {
        await admin.messaging().unsubscribeFromAllTopics([token]);
      } catch (e) {
        console.warn("Could not unsubscribe from topics:", e);
      }

      res.status(200).json({
        success: true,
        message: "Device token deregistered",
      });
    } catch (error) {
      console.error("Error in deregisterDeviceToken:", error);
      res.status(500).json({
        error: "Internal server error",
        details: error instanceof Error ? error.message : String(error),
      });
    }
  });
