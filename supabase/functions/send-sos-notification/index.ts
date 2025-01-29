import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { SignJWT } from "https://deno.land/x/jose@v4.9.1/jwt/sign.ts";
import { importPKCS8 } from "https://deno.land/x/jose@v4.9.1/key/import.ts";

// Import service account from environment variable
const serviceAccountEnv = Deno.env.get("GOOGLE_SERVICE_ACCOUNT");
if (!serviceAccountEnv) {
  throw new Error("GOOGLE_SERVICE_ACCOUNT environment variable is not set.");
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountEnv);
} catch (error) {
  console.error("Failed to parse GOOGLE_SERVICE_ACCOUNT:", error);
  throw new Error("Invalid GOOGLE_SERVICE_ACCOUNT format.");
}

async function getAccessToken(): Promise<string> {
  try {
    console.log("Getting access token...");
    const privateKey = await importPKCS8(serviceAccount.private_key, 'RS256');
    const now = Math.floor(Date.now() / 1000);

    const jwt = await new SignJWT({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
    })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuedAt(now)
      .setExpirationTime(now + 3600)
      .setNotBefore(now)
      .sign(privateKey);

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });

    if (!tokenResponse.ok) {
      const error = await tokenResponse.text();
      throw new Error(`Failed to get access token: ${error}`);
    }

    const { access_token } = await tokenResponse.json();
    console.log("Access token obtained");
    return access_token;
  } catch (error) {
    console.error("Error getting access token:", error);
    throw error;
  }
}

async function sendFCMMessage(token: string, accessToken: string, data: any) {
  try {
    console.log("Sending FCM message...");
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    const message = {
      message: {
        token: token,
        notification: {
          title: "SOS Alert!",
          body: `${data.childName} has triggered an SOS alert!`
        },
        android: {
          priority: "high",
          notification: {
            channelId: "high_importance_channel",
            sound: "default",
            defaultSound: true,
            defaultVibrateTimings: true,
            notificationPriority: "PRIORITY_MAX"
          }
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: "SOS Alert!",
                body: `${data.childName} has triggered an SOS alert!`
              },
              sound: "default",
              badge: 1,
              'content-available': 1,
              priority: 10,
              'mutable-content': 1
            }
          },
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert'
          }
        },
        data: {
          type: "sos_alert",
          childId: data.childId,
          latitude: data.latitude.toString(),
          longitude: data.longitude.toString(),
          click_action: "FLUTTER_NOTIFICATION_CLICK"
        },
        webpush: {
          headers: {
            Urgency: "high",
            TTL: "86400"
          }
        }
      }
    };

    console.log("FCM Message payload:", JSON.stringify(message, null, 2));

    const fcmResponse = await fetch(fcmEndpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message)
    });

    if (!fcmResponse.ok) {
      const error = await fcmResponse.json();
      throw new Error(`FCM send failed: ${JSON.stringify(error)}`);
    }

    const result = await fcmResponse.json();
    console.log("FCM message sent successfully:", result);
    return result;
  } catch (error) {
    console.error("Error sending FCM message:", error);
    throw error;
  }
}

serve(async (req) => {
  try {
    console.log("Processing SOS notification request...");

    const body = await req.json();
    console.log("Request data:", {
      childId: body.childId,
      parentId: body.parentId,
      childName: body.childName,
      location: { lat: body.latitude, lng: body.longitude }
    });

    if (!body.childId || !body.parentId || !body.latitude || !body.longitude) {
      throw new Error("Missing required fields in the request body.");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    console.log("Fetching parent FCM token...");
    const parentResponse = await fetch(
      `${supabaseUrl}/rest/v1/users?user_id=eq.${body.parentId}&select=fcm_token`,
      {
        headers: {
          "Authorization": `Bearer ${supabaseKey}`,
          "apikey": supabaseKey,
        },
      }
    );

    if (!parentResponse.ok) {
      throw new Error("Failed to fetch parent data");
    }

    const parentData = await parentResponse.json();
    if (!parentData[0]?.fcm_token) {
      throw new Error("Parent FCM token not found");
    }

    console.log("Parent FCM token found");

    const accessToken = await getAccessToken();
    const fcmResult = await sendFCMMessage(parentData[0].fcm_token, accessToken, body);

    return new Response(
      JSON.stringify({
        success: true,
        message: "SOS alert sent successfully",
        fcmResult
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 200
      }
    );

  } catch (error: any) {
    console.error("Error processing request:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || "Unknown error",
        stack: error.stack || null
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 400
      }
    );
  }
});