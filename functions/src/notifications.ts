// Firebase Cloud Function for sending push notifications
// Deploy with: firebase deploy --only functions:sendPushNotifications

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { createClient } from "@supabase/supabase-js";

admin.initializeApp();

const supabaseUrl = process.env.SUPABASE_URL || "";
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE || "";
const supabase = createClient(supabaseUrl, supabaseKey);

interface NotificationPayload {
  notification_id: string;
  title: string;
  body: string;
  type: string;
  data: Record<string, string>;
}

interface TargetCriteria {
  notification_id: string;
  target_roles?: string[];
  target_countries?: string[];
}

/**
 * Send push notifications to filtered users
 * Triggered manually or on notification schedule
 */
export const sendPushNotifications = functions
  .region("us-east1")
  .pubsub.schedule("every 5 minutes")
  .onRun(async () => {
    try {
      // Get all scheduled notifications ready to send
      const { data: notifications, error } = await supabase
        .from("notifications")
        .select("*")
        .eq("status", "scheduled")
        .lte("scheduled_at", new Date().toISOString())
        .limit(10);

      if (error) {
        console.error("Error fetching notifications:", error);
        return;
      }

      if (!notifications || notifications.length === 0) {
        console.log("No notifications to send");
        return;
      }

      for (const notification of notifications) {
        await sendNotificationToUsers(notification);
      }
    } catch (error) {
      console.error("Error in sendPushNotifications:", error);
    }
  });

/**
 * HTTP endpoint to manually trigger notification sending
 * POST /sendNotification
 * Body: { notification_id: string }
 */
export const sendNotification = functions
  .region("us-east1")
  .https.onCall(async (data, context) => {
    // Verify caller is authenticated
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated"
      );
    }

    // Verify caller is admin
    const isAdmin = await isUserAdmin(context.auth.uid);
    if (!isAdmin) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Only admins can send notifications"
      );
    }

    const { notification_id } = data;
    if (!notification_id) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "notification_id is required"
      );
    }

    try {
      // Fetch notification
      const { data: notification, error } = await supabase
        .from("notifications")
        .select("*")
        .eq("id", notification_id)
        .single();

      if (error || !notification) {
        throw new functions.https.HttpsError(
          "not-found",
          "Notification not found"
        );
      }

      // Send to users
      const result = await sendNotificationToUsers(notification);

      return {
        success: true,
        message: `Notification sent to ${result.sentCount} users`,
        results: result,
      };
    } catch (error) {
      console.error("Error sending notification:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send notification"
      );
    }
  });

/**
 * Send notification to all matching users
 */
async function sendNotificationToUsers(notification: any) {
  try {
    const targetCriteria: TargetCriteria = {
      notification_id: notification.id,
      target_roles: notification.target_roles,
      target_countries: notification.target_countries,
    };

    // Get all matching device tokens
    const tokens = await getMatchingDeviceTokens(targetCriteria);

    if (tokens.length === 0) {
      console.log("No matching devices for notification:", notification.id);
      return { sentCount: 0, failedCount: 0 };
    }

    // Update notification total_recipients
    await supabase
      .from("notifications")
      .update({ total_recipients: tokens.length })
      .eq("id", notification.id);

    // Build FCM payload
    const payload = buildFCMPayload(notification);

    // Send in batches (FCM has rate limits)
    const batchSize = 500;
    let sentCount = 0;
    let failedCount = 0;

    for (let i = 0; i < tokens.length; i += batchSize) {
      const batch = tokens.slice(i, i + batchSize);
      const responses = await Promise.allSettled(
        batch.map((token) => sendToDevice(token, payload, notification))
      );

      responses.forEach((response) => {
        if (response.status === "fulfilled") {
          sentCount++;
        } else {
          failedCount++;
          console.error("Failed to send:", response.reason);
        }
      });
    }

    // Update notification status
    await supabase
      .from("notifications")
      .update({
        status: "sent",
        total_sent: sentCount,
        sent_at: new Date().toISOString(),
      })
      .eq("id", notification.id);

    console.log(
      `Notification ${notification.id} sent to ${sentCount} devices (${failedCount} failed)`
    );

    return { sentCount, failedCount };
  } catch (error) {
    console.error("Error in sendNotificationToUsers:", error);
    throw error;
  }
}

/**
 * Get device tokens matching target criteria
 */
async function getMatchingDeviceTokens(
  criteria: TargetCriteria
): Promise<string[]> {
  try {
    let query = supabase
      .from("notification_device_tokens")
      .select("fcm_token")
      .eq("is_active", true);

    // Filter by roles if specified
    if (criteria.target_roles && criteria.target_roles.length > 0) {
      // Join with users table to filter by role
      const { data: userIds } = await supabase
        .from("users")
        .select("id")
        .in("role", criteria.target_roles);

      if (!userIds || userIds.length === 0) {
        return [];
      }

      const ids = userIds.map((u: any) => u.id);
      query = query.in("user_id", ids);
    }

    // Filter by countries if specified
    if (criteria.target_countries && criteria.target_countries.length > 0) {
      query = query.in("country_code", criteria.target_countries);
    }

    const { data, error } = await query;

    if (error) {
      console.error("Error fetching device tokens:", error);
      return [];
    }

    return (data || []).map((d: any) => d.fcm_token);
  } catch (error) {
    console.error("Error in getMatchingDeviceTokens:", error);
    return [];
  }
}

/**
 * Build FCM payload
 */
function buildFCMPayload(notification: any) {
  return {
    notification: {
      title: notification.title,
      body: notification.body,
    },
    data: {
      notification_id: notification.id,
      type: notification.notification_type,
      ...(notification.payload || {}),
    },
    android: {
      priority: "high",
      notification: {
        sound: "default",
        channelId: "default",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
    },
  };
}

/**
 * Send to single device
 */
async function sendToDevice(
  token: string,
  payload: any,
  notification: any
): Promise<void> {
  try {
    const response = await admin.messaging().send({
      token,
      ...payload,
    });

    console.log("FCM message sent:", response);

    // Log to database
    await supabase.from("notification_recipients").insert({
      notification_id: notification.id,
      device_token_id: token,
      status: "sent",
      sent_at: new Date().toISOString(),
    });
  } catch (error) {
    console.error("Error sending to device:", error);
    throw error;
  }
}

/**
 * Check if user is admin
 */
async function isUserAdmin(userId: string): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from("users")
      .select("role")
      .eq("id", userId)
      .single();

    if (error || !data) return false;
    return data.role === "admin";
  } catch (error) {
    console.error("Error checking admin status:", error);
    return false;
  }
}

/**
 * Handle FCM token refresh
 * Triggered by Cloud Task when token is refreshed on device
 */
export const handleTokenRefresh = functions
  .region("us-east1")
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated"
      );
    }

    const { old_token, new_token } = data;
    if (!old_token || !new_token) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "old_token and new_token are required"
      );
    }

    try {
      // Update in database
      const { data: token, error } = await supabase
        .from("notification_device_tokens")
        .select("id, user_id")
        .eq("fcm_token", old_token)
        .single();

      if (error || !token) {
        console.log("Token not found in database:", old_token);
        return { success: true };
      }

      // Update to new token
      await supabase
        .from("notification_device_tokens")
        .update({
          fcm_token: new_token,
          last_updated: new Date().toISOString(),
        })
        .eq("id", token.id);

      return { success: true, message: "Token refreshed" };
    } catch (error) {
      console.error("Error handling token refresh:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to refresh token"
      );
    }
  });
