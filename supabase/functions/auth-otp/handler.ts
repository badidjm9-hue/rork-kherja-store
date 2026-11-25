// Request handler for the auth-otp edge function. All I/O (database, Supabase Auth, SMS, clock,
// environment) is injected through `Deps`, so the full security behaviour can be tested without
// Deno or a live Supabase project. index.ts wires the real implementations.

import { displayPhone, emailForPhone, normalizePhone } from "./phone.ts";
import {
  FAILURE_WINDOW_MINUTES,
  normalizeEmail,
  hashClientIp,
  hashOtpInput,
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
  /** Atomically checks phone/IP windows and reserves one attempt; null means rate limited. */
  reserveAttempt(
    phone: string, kind: AttemptKind, windowSeconds: number, phoneLimit: number,
    failuresOnly: boolean, ipHash: string, ipLimit: number,
  ): Promise<number | null>;
  finishAttempt(attemptId: number, success: boolean): Promise<void>;
  saveOtp(phone: string, codeHash: string, expiresAtIso: string, createdAtIso: string): Promise<void>;
  getOtp(phone: string): Promise<{ code_hash: string; expires_at: string } | null>;
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
const PASSWORD_WINDOW_MS = FAILURE_WINDOW_MINUTES * 60 * 1000;
const IP_REQUEST_LIMIT = 20;
const IP_AUTH_LIMIT = 30;

async function reserveForRequest(
  req: Request,
  deps: Deps,
  phone: string,
  kind: AttemptKind,
  windowMs: number,
  phoneLimit: number,
  failuresOnly: boolean,
  ipLimit: number,
): Promise<number | null> {
  const pepper = deps.env("OTP_HASH_SECRET");
  if (!pepper || pepper.length < 32) throw new Error("OTP_HASH_SECRET is not configured");
  // Supabase's Cloudflare edge supplies this header. Do not fall back to a client-controlled
  // X-Forwarded-For value: missing trusted network identity fails closed.
  const ip = req.headers.get("cf-connecting-ip")?.trim();
  if (!ip || ip.length > 64) throw new Error("Trusted client IP header is unavailable");
  const ipHash = await hashClientIp(pepper, ip);
  return deps.store.reserveAttempt(
    phone, kind, Math.ceil(windowMs / 1000), phoneLimit, failuresOnly, ipHash, ipLimit,
  );
}

export function createHandler(deps: Deps) {
  const { store } = deps;

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
        const attemptId = await reserveForRequest(
          req, deps, phone, "password", PASSWORD_WINDOW_MS, 5, true, IP_AUTH_LIMIT,
        );
        if (attemptId === null) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);

        const session = await store.passwordSession(emailForPhone(phone), password);
        await store.finishAttempt(attemptId, !!session);
        // Same message for unknown number, wrong password or no password set (no account enumeration).
        if (!session) return bad();
        return json({ ok: true, ...session, is_new: false });
      }

      // ---------- request an SMS code ----------
      if (action === "request") {
        const attemptId = await reserveForRequest(
          req, deps, phone, "otp_request", REQUEST_WINDOW_MS, REQUEST_LIMIT, false, IP_REQUEST_LIMIT,
        );
        if (attemptId === null) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);

        const otp = deps.generateCode();
        const pepper = deps.env("OTP_HASH_SECRET")!;
        const codeHash = await hashOtpInput(pepper, phone, otp);
        await store.saveOtp(
          phone,
          codeHash,
          new Date(deps.now() + 10 * 60 * 1000).toISOString(),
          new Date(deps.now()).toISOString(),
        );

        const smsSent = await deps.sendSms(phone, otp);
        await store.finishAttempt(attemptId, smsSent);
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
        const attemptId = await reserveForRequest(
          req, deps, phone, "otp_verify", PASSWORD_WINDOW_MS, 5, true, IP_AUTH_LIMIT,
        );
        if (attemptId === null) return json({ error: "Trop de tentatives, réessayez plus tard" }, 429);

        const row = await store.getOtp(phone);
        if (!row) return json({ error: "Code introuvable, demandez un nouveau code" }, 400);
        if (new Date(row.expires_at).getTime() < deps.now()) {
          await store.deleteOtp(phone);
          return json({ error: "Code expiré, demandez un nouveau code" }, 400);
        }
        const pepper = deps.env("OTP_HASH_SECRET")!;
        const suppliedHash = typeof code === "string" ? await hashOtpInput(pepper, phone, code) : "";
        if (typeof code !== "string" || !safeEqual(suppliedHash, row.code_hash)) {
          await store.finishAttempt(attemptId, false);
          return json({ error: "Code incorrect" }, 400);
        }

        const purpose = parsePurpose(body.purpose);
        if (!purpose) {
          await store.finishAttempt(attemptId, true);
          return json({ error: "Action inconnue" }, 400);
        }

        // Validate everything BEFORE consuming the code, so a weak password or a wrong purpose
        // does not burn a valid code.
        const hasPassword = password !== undefined && password !== null && password !== "";
        if (hasPassword && purpose !== "login") {
          const pwError = validatePassword(password);
          if (pwError) {
            await store.finishAttempt(attemptId, true);
            return json({ error: pwError }, 400);
          }
        }
        const contactEmail = normalizeEmail(rawEmail);
        if (contactEmail === null) {
          await store.finishAttempt(attemptId, true);
          return json({ error: "Adresse e-mail invalide" }, 400);
        }

        const email = emailForPhone(phone);
        let userId = await store.findUserIdByEmail(email);
        const decision = decidePurpose({ purpose, userExists: !!userId, hasPassword });
        if (!decision.ok) {
          await store.finishAttempt(attemptId, true);
          return json({ error: decision.message }, decision.status);
        }

        await store.finishAttempt(attemptId, true);
        await store.deleteOtp(phone);

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
