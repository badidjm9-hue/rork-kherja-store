// Supabase Database Webhook receiver for INSERTs into public.notifications.
// Configure a Database Webhook on notifications (INSERT) with header
// x-kherja-push-secret = PUSH_WEBHOOK_SECRET. No provider credentials are committed.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type Device = { id: string; platform: "android" | "ios"; token: string };
type NotificationRecord = { id: string; user_id: string; title: string; body: string; data?: Record<string, unknown> };

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function stringData(input: Record<string, unknown> | undefined): Record<string, string> {
  const output: Record<string, string> = {};
  for (const [key, value] of Object.entries(input ?? {})) {
    if (/^[a-zA-Z0-9_.-]{1,64}$/.test(key)) output[key] = typeof value === "string" ? value : JSON.stringify(value) ?? String(value);
  }
  return output;
}

let fcmCache: { token: string; expiresAt: number } | null = null;
async function fcmAccessToken(): Promise<string> {
  if (fcmCache && fcmCache.expiresAt > Date.now() + 60_000) return fcmCache.token;
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("FCM_NOT_CONFIGURED");
  const account = JSON.parse(raw);
  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error("FCM_OAUTH_FAILED");
  const result = await response.json();
  fcmCache = { token: result.access_token, expiresAt: Date.now() + Number(result.expires_in ?? 3600) * 1000 };
  return fcmCache.token;
}

let apnsCache: { token: string; issuedAt: number } | null = null;
async function apnsProviderToken(): Promise<string> {
  if (apnsCache && Date.now() - apnsCache.issuedAt < 50 * 60 * 1000) return apnsCache.token;
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (!keyId || !teamId || !privateKey) throw new Error("APNS_NOT_CONFIGURED");
  const key = await importPKCS8(privateKey, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId, typ: "JWT" })
    .setIssuer(teamId)
    .setIssuedAt()
    .sign(key);
  apnsCache = { token, issuedAt: Date.now() };
  return token;
}

async function sendAndroid(device: Device, record: NotificationRecord): Promise<{ ok: boolean; invalidToken: boolean }> {
  const account = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!);
  const accessToken = await fcmAccessToken();
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token: device.token,
        notification: { title: record.title, body: record.body },
        data: { notification_id: record.id, ...stringData(record.data) },
        android: { priority: "HIGH", notification: { channel_id: "kherja_updates" } },
      },
    }),
  });
  if (response.ok) return { ok: true, invalidToken: false };
  const result = await response.json().catch(() => null);
  return { ok: false, invalidToken: result?.error?.status === "UNREGISTERED" };
}

async function sendIos(device: Device, record: NotificationRecord): Promise<{ ok: boolean; invalidToken: boolean }> {
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  if (!bundleId) throw new Error("APNS_BUNDLE_ID_NOT_CONFIGURED");
  const host = Deno.env.get("APNS_USE_SANDBOX") === "true" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const response = await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      Authorization: `bearer ${await apnsProviderToken()}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title: record.title, body: record.body }, sound: "default" }, data: { notification_id: record.id, ...stringData(record.data) } }),
  });
  return { ok: response.ok, invalidToken: response.status === 410 };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
  const supplied = request.headers.get("x-kherja-push-secret") ?? "";
  if (!expected || !constantTimeEqual(expected, supplied)) return new Response("Unauthorized", { status: 401 });

  try {
    const payload = await request.json();
    const record = payload?.record as NotificationRecord | undefined;
    if (payload?.type !== "INSERT" || payload?.table !== "notifications" || payload?.schema !== "public" ||
        !record?.id || !record.user_id || !record.title) {
      return Response.json({ error: "Invalid notification webhook payload" }, { status: 400 });
    }
    const { data: devices, error } = await supabase
      .from("push_devices").select("id,platform,token").eq("user_id", record.user_id);
    if (error) throw new Error("DEVICE_LOOKUP_FAILED");

    const results = await Promise.all((devices ?? []).map(async (device: Device) => {
      try {
        const delivery = device.platform === "android"
          ? await sendAndroid(device, record)
          : await sendIos(device, record);
        if (delivery.invalidToken) {
          const { error: cleanupError } = await supabase.from("push_devices").delete().eq("id", device.id);
          if (cleanupError) return { id: device.id, ok: false };
        }
        return { id: device.id, ok: delivery.ok };
      } catch {
        return { id: device.id, ok: false };
      }
    }));
    return Response.json({ ok: true, sent: results.filter((r) => r.ok).length, failed: results.filter((r) => !r.ok).length });
  } catch {
    // Do not return tokens, provider response bodies or secrets to the webhook caller.
    return Response.json({ error: "Push delivery failed" }, { status: 500 });
  }
});
