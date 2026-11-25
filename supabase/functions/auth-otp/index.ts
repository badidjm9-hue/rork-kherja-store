// Entry point: wires the real Supabase, Twilio and environment into the tested handler.
// All decisions live in handler.ts / policy.ts; keep this file thin.
//
// Server-side environment (Supabase function secrets):
//   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE   SMS provider (required in production)
//   KHERJA_ENV=development + ALLOW_DEV_OTP=true            development ONLY: return the code in the response
// Anything else is treated as production and never exposes a verification code.

import { createClient } from "npm:@supabase/supabase-js@2";
import { createHandler, type SessionTokens, type Store } from "./handler.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

async function sendSms(phone: string, code: string): Promise<boolean> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_PHONE");
  if (!sid || !token || !from) return false;
  try {
    const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: "Basic " + btoa(`${sid}:${token}`),
      },
      body: new URLSearchParams({
        To: phone,
        From: from,
        Body: `KHERJA — votre code de vérification est ${code}`,
      }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

function toTokens(session: Record<string, unknown>, userId: string | null): SessionTokens | null {
  const access = session.access_token;
  const refresh = session.refresh_token;
  if (typeof access !== "string" || typeof refresh !== "string") return null;
  return {
    access_token: access,
    refresh_token: refresh,
    expires_in: typeof session.expires_in === "number" ? session.expires_in : null,
    user_id: userId,
  };
}

const store: Store = {
  async countAttempts(phone, kind, sinceIso, onlyFailures) {
    let q = admin
      .from("auth_login_attempts")
      .select("id", { count: "exact", head: true })
      .eq("phone", phone)
      .eq("kind", kind)
      .gte("attempted_at", sinceIso);
    if (onlyFailures) q = q.eq("success", false);
    const { count } = await q;
    return count ?? 0;
  },

  async recordAttempt(phone, kind, success) {
    await admin.from("auth_login_attempts").insert({ phone, kind, success });
  },

  async saveOtp(phone, code, expiresAtIso, createdAtIso) {
    await admin.from("otp_codes").upsert({ phone, code, expires_at: expiresAtIso, created_at: createdAtIso });
  },

  async getOtp(phone) {
    const { data } = await admin.from("otp_codes").select("code, expires_at").eq("phone", phone).single();
    return data ?? null;
  },

  async deleteOtp(phone) {
    await admin.from("otp_codes").delete().eq("phone", phone);
  },

  async findUserIdByEmail(email) {
    for (let page = 1; page <= 10; page++) {
      const { data } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
      const match = data.users.find((u) => u.email === email);
      if (match) return match.id;
      if (data.users.length < 1000) break;
    }
    return null;
  },

  async createUser(email, metadata) {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: metadata,
    });
    if (error || !data.user) return null;
    return data.user.id;
  },

  async updateUser(userId, changes) {
    const attrs: { password?: string; user_metadata?: Record<string, unknown> } = {};
    // Supabase Auth hashes the password (bcrypt); we never store or log it.
    if (changes.password) attrs.password = changes.password;
    if (changes.contactEmail) {
      // Merge explicitly so existing metadata (phone, display_phone) is never dropped.
      const { data: existing } = await admin.auth.admin.getUserById(userId);
      attrs.user_metadata = { ...(existing?.user?.user_metadata ?? {}), contact_email: changes.contactEmail };
    }
    const { error } = await admin.auth.admin.updateUserById(userId, attrs);
    return !error;
  },

  // Mint a real Supabase session via admin magic-link (never delivered by mail).
  async mintSession(email, userId) {
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (linkError || !link?.properties) return null;
    const otpToken = link.properties.email_otp
      ?? new URL(link.properties.action_link).searchParams.get("token");
    if (!otpToken) return null;
    const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/verify`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: Deno.env.get("SUPABASE_ANON_KEY")! },
      body: JSON.stringify({ type: "magiclink", email, token: otpToken }),
    });
    if (!res.ok) return null;
    return toTokens(await res.json(), userId);
  },

  async passwordSession(email, password) {
    const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: Deno.env.get("SUPABASE_ANON_KEY")! },
      body: JSON.stringify({ email, password }),
    });
    if (!res.ok) return null;
    const session = await res.json();
    return toTokens(session, session?.user?.id ?? null);
  },
};

Deno.serve(
  createHandler({
    env: (key) => Deno.env.get(key),
    now: () => Date.now(),
    generateCode: () => String(100000 + crypto.getRandomValues(new Uint32Array(1))[0] % 900000),
    sendSms,
    store,
  }),
);
