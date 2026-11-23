import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Normalise Algerian numbers to E.164 (+213).
function normalizePhone(raw: string): string | null {
  const digits = raw.replace(/[\s()-]/g, "");
  let e164: string;
  if (digits.startsWith("+213")) e164 = digits;
  else if (digits.startsWith("213")) e164 = "+" + digits;
  else if (digits.startsWith("0")) e164 = "+213" + digits.slice(1);
  else return null;
  if (!/^\+213[5-7]\d{8}$/.test(e164)) return null;
  return e164;
}

function displayPhone(e164: string): string {
  // +213555123456 -> 0555 12 34 56
  const local = "0" + e164.slice(4);
  return `${local.slice(0, 4)} ${local.slice(4, 6)} ${local.slice(6, 8)} ${local.slice(8, 10)}`;
}

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

// Each phone number maps to a synthetic, auto-confirmed email identity so
// Supabase mints a real session (refreshable, recognised by RLS/Realtime).
function emailForPhone(phone: string): string {
  return `u${phone.replace(/[^0-9]/g, "")}@phone.kherja.app`;
}

async function findUserByEmail(admin: ReturnType<typeof createClient>, email: string): Promise<string | null> {
  for (let page = 1; page <= 10; page++) {
    const { data } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    const match = data.users.find((u) => u.email === email);
    if (match) return match.id;
    if (data.users.length < 1000) break;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { action, phone: rawPhone, code } = await req.json();
    const phone = normalizePhone(rawPhone ?? "");
    if (!phone) return json({ error: "Numéro invalide" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    if (action === "request") {
      // Basic rate limit: 3 codes per phone per 5 minutes.
      const { count } = await admin
        .from("otp_codes")
        .select("phone", { count: "exact", head: true })
        .eq("phone", phone)
        .gte("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString());
      if ((count ?? 0) >= 3) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);

      const otp = String(Math.floor(100000 + Math.random() * 900000));
      await admin.from("otp_codes").upsert({
        phone,
        code: otp,
        expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
        created_at: new Date().toISOString(),
      });

      const smsSent = await sendSms(phone, otp);
      if (smsSent) return json({ ok: true, phone: displayPhone(phone), dev_code: null });
      // No SMS provider configured — development mode returns the code directly.
      return json({ ok: true, phone: displayPhone(phone), dev_code: otp, dev: true });
    }

    if (action === "verify") {
      const { data: row } = await admin
        .from("otp_codes")
        .select("code, expires_at")
        .eq("phone", phone)
        .single();
      if (!row) return json({ error: "Code introuvable, demandez un nouveau code" }, 400);
      if (new Date(row.expires_at) < new Date()) {
        await admin.from("otp_codes").delete().eq("phone", phone);
        return json({ error: "Code expiré, demandez un nouveau code" }, 400);
      }
      if (row.code !== code) return json({ error: "Code incorrect" }, 400);
      await admin.from("otp_codes").delete().eq("phone", phone);

      // Create or find the auth user for this phone.
      const email = emailForPhone(phone);
      let userId = await findUserByEmail(admin, email);
      let isNew = false;
      if (!userId) {
        const { data: created, error } = await admin.auth.admin.createUser({
          email,
          email_confirm: true,
          user_metadata: { phone, display_phone: displayPhone(phone) },
        });
        if (error || !created.user) return json({ error: "Création du compte impossible" }, 500);
        userId = created.user.id;
        isNew = true;
      }

      // Mint a real Supabase session via admin magic-link (never delivered by mail).
      const { data: link, error: linkError } = await admin.auth.admin.generateLink({
        type: "magiclink",
        email,
      });
      if (linkError || !link?.properties) return json({ error: "Session impossible" }, 500);
      const otpToken = link.properties.email_otp
        ?? new URL(link.properties.action_link).searchParams.get("token");
      if (!otpToken) return json({ error: "Session impossible" }, 500);

      const verifyRes = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/verify`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: Deno.env.get("SUPABASE_ANON_KEY")!,
        },
        body: JSON.stringify({ type: "magiclink", email, token: otpToken }),
      });
      if (!verifyRes.ok) return json({ error: "Session impossible" }, 500);
      const session = await verifyRes.json();
      if (!session.access_token || !session.refresh_token) {
        return json({ error: "Session impossible" }, 500);
      }

      return json({
        ok: true,
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        expires_in: session.expires_in,
        user_id: userId,
        is_new: isNew,
      });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("auth-otp error:", err);
    return json({ error: "Erreur serveur" }, 500);
  }
});
