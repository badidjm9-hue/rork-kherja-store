// Request handler for the auth-otp edge function. All I/O (database, Supabase Auth, SMS, clock,
// environment) is injected through `Deps`, so the full security behaviour can be tested without
// Deno or a live Supabase project. index.ts wires the real implementations.

import { displayPhone, emailForPhone, normalizePhone } from "./phone.ts";
import {
  FAILURE_WINDOW_MINUTES,
  isBlocked,
  normalizeEmail,
  safeEqual,
  validatePassword,
} from "./password.ts";
import { decideOtpDelivery, decidePurpose, devOtpAllowed, parsePurpose } from "./policy.ts";

export interface SessionTokens {
  access_token: string;
  refresh_token: string;
  expires_in: number | null;
  user_id: string | null;
}

export type AttemptKind = "password" | "otp_verify" | "otp_request";

export interface Store {
  /** `onlyFailures` counts rows with success=false; otherwise all rows. */
  countAttempts(phone: string, kind: AttemptKind, sinceIso: string, onlyFailures: boolean): Promise<number>;
  recordAttempt(phone: string, kind: AttemptKind, success: boolean): Promise<void>;
  saveOtp(phone: string, code: string, expiresAtIso: string, createdAtIso: string): Promise<void>;
  getOtp(phone: string): Promise<{ code: string; expires_at: string } | null>;
  deleteOtp(phone: string): Promise<void>;
  findUserIdByEmail(email: string): Promise<string | null>;
  createUser(email: string, metadata: Record<string, unknown>): Promise<string | null>;
  /** Sets the password (hashed by Supabase Auth) and/or merges a contact e-mail into metadata. */
  updateUser(userId: string, changes: { password?: string; contactEmail?: string }): Promise<boolean>;
  /** Mints a real Supabase session for an already-proven phone identity. */
  mintSession(email: string, userId: string): Promise<SessionTokens | null>;
  /** Password grant against Supabase Auth. Returns null on any failure. */
  passwordSession(email: string, password: string): Promise<SessionTokens | null>;
}

export interface Deps {
  env: (key: string) => string | undefined;
  now: () => number;
  generateCode: () => string;
  /** True only when the SMS provider confirmed delivery. False when unconfigured or failed. */
  sendSms: (phone: string, code: string) => Promise<boolean>;
  store: Store;
}

export const corsHeaders = {
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

const REQUEST_LIMIT = 3;
const REQUEST_WINDOW_MS = 5 * 60 * 1000;

export function createHandler(deps: Deps) {
  const { store } = deps;
  const sinceFailures = () => new Date(deps.now() - FAILURE_WINDOW_MINUTES * 60 * 1000).toISOString();

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

    try {
      // Only these fields are read. Nothing in the body or headers can switch on a development
      // behaviour: that is decided solely by server-side environment (see policy.ts).
      const body = await req.json();
      const { action, phone: rawPhone, code, password, email: rawEmail } = body ?? {};
      const phone = normalizePhone(typeof rawPhone === "string" ? rawPhone : "");
      if (!phone) return json({ error: "Numéro invalide" }, 400);

      // ---------- phone + password sign-in ----------
      if (action === "login") {
        const bad = () => json({ error: "Numéro ou mot de passe incorrect" }, 401);
        if (typeof password !== "string" || password.length === 0) return bad();
        const failures = await store.countAttempts(phone, "password", sinceFailures(), true);
        if (isBlocked(failures)) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);

        const session = await store.passwordSession(emailForPhone(phone), password);
        await store.recordAttempt(phone, "password", !!session);
        // Same message for unknown number, wrong password or no password set (no account enumeration).
        if (!session) return bad();
        return json({ ok: true, ...session, is_new: false });
      }

      // ---------- request an SMS code ----------
      if (action === "request") {
        const recent = await store.countAttempts(
          phone,
          "otp_request",
          new Date(deps.now() - REQUEST_WINDOW_MS).toISOString(),
          false,
        );
        if (recent >= REQUEST_LIMIT) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);
        await store.recordAttempt(phone, "otp_request", true);

        const otp = deps.generateCode();
        await store.saveOtp(
          phone,
          otp,
          new Date(deps.now() + 10 * 60 * 1000).toISOString(),
          new Date(deps.now()).toISOString(),
        );

        const smsSent = await deps.sendSms(phone, otp);
        const delivery = decideOtpDelivery({ smsSent, devAllowed: devOtpAllowed(deps.env) });

        if (delivery.kind === "sent") return json({ ok: true, phone: displayPhone(phone), dev_code: null });
        if (delivery.kind === "dev_code") {
          return json({ ok: true, phone: displayPhone(phone), dev_code: otp, dev: true });
        }
        // Production without a working SMS provider: discard the code and fail securely.
        await store.deleteOtp(phone);
        return json({ error: delivery.message }, delivery.status);
      }

      // ---------- verify the SMS code (login / register / reset) ----------
      if (action === "verify") {
        const failures = await store.countAttempts(phone, "otp_verify", sinceFailures(), true);
        if (isBlocked(failures)) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);

        const row = await store.getOtp(phone);
        if (!row) return json({ error: "Code introuvable, demandez un nouveau code" }, 400);
        if (new Date(row.expires_at).getTime() < deps.now()) {
          await store.deleteOtp(phone);
          return json({ error: "Code expiré, demandez un nouveau code" }, 400);
        }
        if (typeof code !== "string" || !safeEqual(row.code, code)) {
          await store.recordAttempt(phone, "otp_verify", false);
          return json({ error: "Code incorrect" }, 400);
        }

        const purpose = parsePurpose(body.purpose);
        if (!purpose) return json({ error: "Action inconnue" }, 400);

        // Validate everything BEFORE consuming the code, so a weak password or a wrong purpose
        // does not burn a valid code.
        const hasPassword = password !== undefined && password !== null && password !== "";
        if (hasPassword && purpose !== "login") {
          const pwError = validatePassword(password);
          if (pwError) return json({ error: pwError }, 400);
        }
        const contactEmail = normalizeEmail(rawEmail);
        if (contactEmail === null) return json({ error: "Adresse e-mail invalide" }, 400);

        const email = emailForPhone(phone);
        let userId = await store.findUserIdByEmail(email);
        const decision = decidePurpose({ purpose, userExists: !!userId, hasPassword });
        if (!decision.ok) return json({ error: decision.message }, decision.status);

        await store.deleteOtp(phone);
        await store.recordAttempt(phone, "otp_verify", true);

        let isNew = false;
        if (!userId) {
          userId = await store.createUser(email, { phone, display_phone: displayPhone(phone) });
          if (!userId) return json({ error: "Création du compte impossible" }, 500);
          isNew = true;
        }

        if (hasPassword || contactEmail) {
          const updated = await store.updateUser(userId, {
            password: hasPassword ? (password as string) : undefined,
            contactEmail: contactEmail || undefined,
          });
          if (!updated) return json({ error: "Mise à jour du compte impossible" }, 500);
        }

        const session = await store.mintSession(email, userId);
        if (!session) return json({ error: "Session impossible" }, 500);
        return json({ ok: true, ...session, user_id: userId, is_new: isNew });
      }

      return json({ error: "Unknown action" }, 400);
    } catch (err) {
      // Never log the error object or the request body: either could contain a password or code.
      console.error("auth-otp error:", err instanceof Error ? err.name : "unknown");
      return json({ error: "Erreur serveur" }, 500);
    }
  };
}
